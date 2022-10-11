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
import concurrent
import dataclasses
import json
import logging
import os
import pathlib
import re
import sys
import threading
from typing import Sequence, Optional

from build.kernel.kleaf import buildozer_command_builder

_INCLUDE_DIRECTIVE = r'^\s*#include\s*(<(?P<path1>.*)>|"(?P<path2>.*)")\s*'


def die(*args, **kwargs):
    logging.error(*args, **kwargs)
    sys.exit(1)


def jsonify(object):
    """Make object valid for json.dumps."""
    if isinstance(object, list) or isinstance(object, set):
        return [jsonify(item) for item in object]
    if isinstance(object, dict):
        return {str(key): jsonify(value) for key, value in object.items()}
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
    file: Optional[pathlib.Path]
    include_dir: Optional[pathlib.Path]

    def __bool__(self):
        return bool(self.file) or bool(self.include_dir)


@dataclasses.dataclass()
class FuzzySearchResult(object):
    additional_files: set[pathlib.Path] = dataclasses.field(default_factory=set)
    additional_includes: set[pathlib.Path] = dataclasses.field(default_factory=set)
    unknown_raw_include: set[pathlib.Path] = dataclasses.field(default_factory=set)

    def __ior__(self, other):
        self.additional_files |= other.additional_files
        self.additional_includes |= other.additional_includes
        self.unknown_raw_include |= other.unknown_raw_include
        return self


class GenDdkHeaders(buildozer_command_builder.BuildozerCommandBuilder):
    def __init__(self, *init_args, **init_kwargs):
        super().__init__(*init_args, **init_kwargs)
        self._all_files = [pathlib.Path(e.strip()) for e in self.args.input.readlines()]
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

        sorted_package_files = sorted(
            (package, sorted(files)) for package, files in package_files.items())

        # List of all known include directories, relative to workspace root
        include_dirs: set[pathlib.Path] = set()
        for package, files in sorted_package_files:
            package_include_dirs = self._generate_target(package, "all_headers", files)
            include_dirs |= set(package / e for e in package_include_dirs)

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

            sum_res = FuzzySearchResult()

            pass_num = 0
            while True:
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
                                        include_dirs | sum_res.additional_includes))

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
            self._dump_debug("include_dirs.json", jsonify(list(include_dirs)))
            self._dump_debug("all_headers.json", jsonify(all_headers))

        self._dumped = True

    def _get_package(self, dir: pathlib.Path) -> Optional[pathlib.Path]:
        dir_parts = dir.parts
        for package in self.args.package:
            if dir_parts[:len(package.parts)] == package.parts:
                return package
        return None  # ignore

    def _generate_target(self, package: pathlib.Path, name: str,
                         files: list[pathlib.Path]) -> set[pathlib.Path]:
        target = self._new("ddk_headers", name, str(package))
        self._add_attr(target, "visibility", "//visibility:public", quote=True)
        include_dirs: set[pathlib.Path] = {"."}
        glob_dirs: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)

        for file in sorted(files):
            rel_file = pathlib.Path(*file.parts[len(package.parts):])

            glob_dir = self._get_glob_dir_or_none(rel_file)
            if glob_dir:
                glob_dirs[glob_dir].append(rel_file)
            else:
                self._add_attr(target, "hdrs", str(rel_file), quote=True)

            # add to includes
            try:
                idx = rel_file.parent.parts.index("include")
                include_dirs.add(pathlib.Path(*rel_file.parent.parts[:idx + 1]))
            except ValueError:
                pass

        for dir in include_dirs:
            self._add_attr(target, "includes", dir, quote=True)

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

        return include_dirs

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

    async def _fuzzy_resolve(self, all_headers: list[pathlib.Path],
                             file_raw_includes: dict[pathlib.Path, Optional[list[pathlib.Path]]],
                             known_files: set[pathlib.Path],
                             known_include_dirs: set[pathlib.Path]):
        ret_files = set()
        ret_includes = set()
        unknown = set()

        files = list()
        awaitables = list()
        for file, raw_includes in file_raw_includes.items():
            files.append(file)
            awaitables.append(self._fuzzy_resolve_multi(raw_includes, all_headers))

        all_results = await asyncio.gather(*awaitables)

        for file, results in zip(files, all_results):
            for result in results:
                if result:
                    ret_files.add(result.file)
                    ret_includes.add(result.include_dir)
                else:
                    unknown.add(result.raw_include)

        additional_files = ret_files - known_files
        additional_includes = ret_includes - known_include_dirs
        unknown = unknown

        return FuzzySearchResult(
            additional_files=additional_files,
            additional_includes=additional_includes,
            unknown_raw_include=unknown
        )

    async def _fuzzy_resolve_multi(self, raw_includes: list[pathlib.Path],
                                   all_headers: list[pathlib.Path]):
        res = []
        for raw_include in raw_includes:
            res.append(self._fuzzy_resolve_one(raw_include, all_headers))
        return res

    def _fuzzy_resolve_one(self, want: pathlib.Path, known: list[pathlib.Path]) \
            -> FuzzySearchOneResult:
        want_parts = want.parts
        for known_file in known:
            if len(want_parts) <= len(known_file.parts) and \
                    want.parts == known_file.parts[-len(want_parts):]:
                return FuzzySearchOneResult(want, known_file,
                                            pathlib.Path(*known_file.parts[:-len(want_parts)]))
        return FuzzySearchOneResult(want, None, None)

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
    parser.add_argument("--dump", type=pathlib.Path,
                        help="""A dump file that lists dependencies.""")
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
