# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import asyncio
import collections
import dataclasses
import json
import logging
import os
import pathlib
import re
import sys
from typing import Sequence, Optional, Iterable

from build.kernel.kleaf import buildozer_command_builder

_INCLUDE_DIRECTIVE = r'^\s*#include\s*(<(?P<path1>.*)>|"(?P<path2>.*)")\s*'


def die(*args, **kwargs):
    logging.error(*args, **kwargs)
    sys.exit(1)


def jsonify(object):
    """Make object valid for json.dumps."""
    if isinstance(object, list) or isinstance(object, set):
        return sorted([jsonify(item) for item in object])
    if isinstance(object, dict):
        return collections.OrderedDict(
            sorted((str(key), jsonify(value)) for key, value in object.items()))
    return str(object)


class Numfiles(object):
    """Lazily evaluates to the number of files """

    def __init__(self, path: pathlib.Path):
        self._path = path

    def __int__(self):
        return sum([len(files) for _, _, files in os.walk(self._path)])


@dataclasses.dataclass(frozen=True)
class FuzzySearchOneResult(object):
    raw_include: pathlib.Path
    files: Optional[list[pathlib.Path]]

    def __bool__(self):
        return bool(self.files)


@dataclasses.dataclass()
class FuzzySearchResult(object):
    additional_files: set[pathlib.Path] = dataclasses.field(default_factory=set)
    additional_includes: set[pathlib.Path] = dataclasses.field(default_factory=set)
    additional_files_explained: dict[pathlib.Path, set[pathlib.Path]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(set))
    additional_includes_explained: dict[pathlib.Path, set[pathlib.Path]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(set))
    unknown_raw_include: set[pathlib.Path] = dataclasses.field(default_factory=set)
    known_files_reversed: dict[pathlib.Path, list[pathlib.Path]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(list))
    all_headers_reversed: dict[pathlib.Path, list[pathlib.Path]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(list))

    def __ior__(self, other):
        self.additional_files |= other.additional_files
        self.additional_includes |= other.additional_includes
        for k, v in other.additional_files_explained.items():
            self.additional_files_explained[k] |= v
        for k, v in other.additional_includes_explained.items():
            self.additional_includes_explained[k] |= v
        self.unknown_raw_include |= other.unknown_raw_include
        for k, v in other.known_files_reversed.items():
            self.known_files_reversed[k] += v
        for k, v in other.all_headers_reversed.items():
            self.all_headers_reversed[k] += v
        return self


class GenDdkHeaders(buildozer_command_builder.BuildozerCommandBuilder):
    def __init__(self, *init_args, **init_kwargs):
        super().__init__(*init_args, **init_kwargs)
        self._all_files = [pathlib.Path(e.strip()) for e in self.args.input.readlines()]
        self._all_includes = [pathlib.Path(e.strip()) for e in self.args.input_includes.readlines()]
        self._debug_dump = dict()
        self._dumped = False

    def _create_buildozer_commands(self):
        # package -> files
        package_files: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for file in self._all_files:
            package = self._get_package(file)
            if not package:
                continue
            package_files[package].append(file)

        # package -> include dirs
        package_includes: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for include in self._all_includes:
            package = self._get_package(include)
            if not package:
                continue
            package_includes[package].append(include)

        sorted_package_files = sorted(
            (package, sorted(files)) for package, files in package_files.items())

        # List of all known include directories, relative to workspace root
        for package, files in sorted_package_files:
            # FIXME optimize to avoid lookup?
            self._generate_target(package, "all_headers", files,
                                  package_includes[package])

        # List of all headers in known packages, relative to workspace root
        all_headers = list(
            pathlib.Path(root, file).relative_to(self._workspace_root())
            for package in self.args.package
            for root, dir, files in os.walk(self._workspace_root() / package)
            for file in files
            if file.endswith(".h"))

        # TODO: This should cache results
        for package, files in sorted_package_files:
            files_to_analyze = set(files)
            all_files = set(self._all_files)
            all_includes = set(self._all_includes)

            sum_res = FuzzySearchResult()

            pass_num = 0
            while self.args.fuzz:
                # file -> #include directives. file is relative to workspace root.
                # include_directives is relative to unknown directory that needs
                # to be discovered later.
                file_raw_includes: dict[pathlib.Path, Optional[list[pathlib.Path]]] = {
                    file: self._analyze_include_directives(file)
                    for file in files_to_analyze
                }

                fuzzy_resolve_res: FuzzySearchResult = asyncio.run(
                    self._fuzzy_resolve(all_headers, file_raw_includes,
                                        all_files | sum_res.additional_files,
                                        all_includes | sum_res.additional_includes))

                if not fuzzy_resolve_res.additional_files and not fuzzy_resolve_res.additional_includes:
                    break

                # Sum
                sum_res |= fuzzy_resolve_res

                # Prepare for next run
                files_to_analyze = fuzzy_resolve_res.additional_files

                pass_num += 1
                logging.warning("%s: pass %d, found %d files, %d includes, %d unknowns", package,
                                pass_num,
                                len(fuzzy_resolve_res.additional_files),
                                len(fuzzy_resolve_res.additional_includes),
                                len(fuzzy_resolve_res.unknown_raw_include))

                if not self._dumped:
                    for key, value in vars(fuzzy_resolve_res).items():
                        self._dump_debug(package / str(pass_num) / f"{key}.json", jsonify(value))

            if not self._dumped:
                for key, value in vars(sum_res).items():
                    self._dump_debug(package / f"{key}.json", jsonify(value))

        if not self._dumped:
            self._dump_debug("package_files.json", jsonify(package_files))
            self._dump_debug("package_includes.json", jsonify(package_includes))
            self._dump_debug("all_headers.json", jsonify(all_headers))

        self._dumped = True

    def _get_package(self, dir: pathlib.Path) -> Optional[pathlib.Path]:
        dir_parts = dir.parts
        for package in self.args.package:
            if dir_parts[:len(package.parts)] == package.parts:
                return package
        return None  # ignore

    def _generate_target(self, package: pathlib.Path, name: str,
                         files: list[pathlib.Path],
                         include_dirs: list[pathlib.Path]):
        target = self._new("ddk_headers", name, str(package))
        self._add_attr(target, "visibility", "//visibility:public", quote=True)
        glob_dirs: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)

        for file in sorted(files):
            rel_file = pathlib.Path(*file.parts[len(package.parts):])

            glob_dir = self._get_glob_dir_or_none(rel_file)
            if glob_dir:
                glob_dirs[glob_dir].append(rel_file)
            else:
                self._add_attr(target, "hdrs", str(rel_file), quote=True)

            # add to includes
            # try:
            #     idx = rel_file.parent.parts.index("include")
            #     include_dirs.add(pathlib.Path(*rel_file.parent.parts[:idx + 1]))
            # except ValueError:
            #     pass

        for dir in include_dirs:
            self._add_attr(target, "includes",
                           pathlib.Path(*dir.parts[len(package.parts):]), quote=True)

        if glob_dirs:
            glob_target = self._new("filegroup", name + "_globs", str(package), load_from=None)
            # TODO make incremental; do not delete old glob patterns
            self._set_attr(glob_target, "srcs", """glob([{}])""".format(
                ",\\ ".join([repr(f"{d}/**/*.h") for d in glob_dirs])))
            self._add_attr(glob_target, "visibility", "//visibility:private", quote=True)
            self._add_attr(target, "hdrs", glob_target, quote=True)

            for glob_dir, files in glob_dirs.items():
                logging.info("%s has %d files, globbing %d files",
                             glob_dir, len(files),
                             Numfiles(self._workspace_root() / package / glob_dir))

    def _dump_debug(self, rel_path, object):
        path = self.args.dump / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as fp:
            json.dump(object, fp, indent=4)

    def _get_glob_dir_or_none(self, rel_file) -> Optional[pathlib.Path]:
        rel_file_parts = rel_file.parts
        for glob_dir in self.args.glob:
            if rel_file_parts[:len(glob_dir.parts)] == glob_dir.parts:
                return glob_dir
        return None

    def _analyze_include_directives(self, file) -> Optional[list[pathlib.Path]]:
        file_path = self._workspace_root() / file

        if not file_path.is_file():
            logging.warning("Can't find %s", file_path)
            return None

        ret = list()
        with open(file_path) as fp:
            for line in fp:
                mo = re.match(_INCLUDE_DIRECTIVE, line)
                if not mo:
                    continue
                if mo.group("path1"):
                    ret.append(pathlib.Path(mo.group("path1")))
                if mo.group("path2"):
                    ret.append(pathlib.Path(mo.group("path2")))
        return ret

    @staticmethod
    def _build_reverse_lookup_table(files: Iterable[pathlib.Path]) \
            -> dict[pathlib.Path, list[pathlib.Path]]:

        ret = collections.defaultdict(list)

        for file in files:
            for start in range(-1, -len(file.parts), -1):
                ret[pathlib.Path(*file.parts[start:])].append(file)

        return ret

    async def _fuzzy_resolve(self, all_headers: list[pathlib.Path],
                             file_raw_includes: dict[pathlib.Path, Optional[list[pathlib.Path]]],
                             known_files: set[pathlib.Path],
                             known_include_dirs: set[pathlib.Path]):
        ret_files = collections.defaultdict(set)
        ret_includes = collections.defaultdict(set)
        unknown = set()

        known_files_reversed = type(self)._build_reverse_lookup_table(known_files)
        all_headers_reversed = type(self)._build_reverse_lookup_table(all_headers)

        files = list()
        awaitables = list()
        for file, raw_includes in file_raw_includes.items():
            files.append(file)
            awaitables.append(
                self._fuzzy_resolve_multi(raw_includes, known_files_reversed, all_headers_reversed))

        all_results = await asyncio.gather(*awaitables)

        for file, results in zip(files, all_results):
            for result in results:
                if result:
                    found_matching = False
                    for possible_child in result.files:
                        possible_include_dir = pathlib.Path(
                            *possible_child.parts[:-len(result.raw_include.parts)])
                        if possible_include_dir in known_include_dirs:
                            ret_files[possible_child].add(file)
                            ret_includes[possible_include_dir].add(file)
                            found_matching = True
                            break
                    if not found_matching:
                        # Can't find the file in existing include directories, so this is a new
                        # finding. Add all matched files.
                        for child in result.files:
                            ret_files[child].add(file)
                            ret_includes[pathlib.Path(*child.parts[:-len(result.raw_include.parts)])].add(file)
                else:
                    unknown.add(result.raw_include)

        return FuzzySearchResult(
            additional_files=set(ret_files.keys()) - known_files,
            additional_includes=set(ret_includes.keys()) - known_include_dirs,
            additional_files_explained={k: v for k, v in ret_files.items() if k not in known_files},
            additional_includes_explained={k: v for k, v in ret_includes.items() if
                                           k not in known_include_dirs},
            unknown_raw_include=unknown,
            known_files_reversed=known_files_reversed,
            all_headers_reversed=all_headers_reversed,
        )

    async def _fuzzy_resolve_multi(self, raw_includes: Iterable[pathlib.Path],
                                   known_headers_reversed: dict[pathlib.Path, list[pathlib.Path]],
                                   all_headers_reversed: dict[pathlib.Path, list[pathlib.Path]]):
        res = []
        for raw_include in raw_includes:
            res.append(
                self._fuzzy_resolve_one(raw_include, known_headers_reversed, all_headers_reversed))
        return res

    def _fuzzy_resolve_one(self, want: pathlib.Path,
                           known_reversed: dict[pathlib.Path, list[pathlib.Path]],
                           fallback_reversed: dict[
                               pathlib.Path, list[pathlib.Path]]) -> FuzzySearchOneResult:
        for lookup_table in (known_reversed, fallback_reversed):
            if want in lookup_table:
                return FuzzySearchOneResult(want, lookup_table[want])
        return FuzzySearchOneResult(want, None)

    def _should_dump(self):
        return self.args.dump and not self._dumped


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--input", help="Input list of headers",
                        type=argparse.FileType("r"), default=sys.stdin)
    parser.add_argument("--input_includes", help="Input list of includes",
                        type=argparse.FileType("r"), default=sys.stdin)
    parser.add_argument("-v", "--verbose", help="verbose mode", action="store_true")
    parser.add_argument("-k", "--keep-going",
                        help="buildozer keeps going on errors.",
                        action="store_true")
    parser.add_argument("--stdout",
                        help="buildozer writes changed BUILD file to stdout (dry run)",
                        action="store_true")
    parser.add_argument("--package", nargs="*", type=pathlib.Path,
                        help="""List of known packages. If an input file is found in the known
                                package, subpackage will not be created. Only input files
                                in known packages are considered; others are silently ignored.""",
                        default=[pathlib.Path("common")])
    parser.add_argument("--glob", nargs="*", type=pathlib.Path,
                        help="""List of paths under --package that should be globbed instead
                                of listing individual files.""",
                        default=[pathlib.Path(e) for e in []])
    parser.add_argument("--fuzz", action="store_true",
                        help="""Fuzzily search for transitive includes""")
    parser.add_argument("--dump", type=pathlib.Path,
                        help="""Directory that stores debug info.""")
    # TODO:
    # "include/asm-generic",
    # "include/linux",
    # "include/uapi/linux",
    # "arch/arm64/include",
    return parser.parse_args(argv)


def main(argv: Sequence[str]):
    args = parse_args(argv)
    log_level = logging.INFO if args.verbose else logging.WARNING
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    GenDdkHeaders(args=args).run()


if __name__ == "__main__":
    main(sys.argv[1:])
