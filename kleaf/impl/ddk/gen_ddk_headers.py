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
import textwrap
from typing import Sequence, Optional, Iterable, Any, NoReturn, Callable

from build.kernel.kleaf import buildozer_command_builder

_INCLUDE_DIRECTIVE = r'^\s*#include\s*(<(?P<path1>.*)>|"(?P<path2>.*)")\s*'

Paths = set[pathlib.Path]
PathsWithSourcesType = dict[pathlib.Path, Paths]
PathsWithSources = lambda: collections.defaultdict(set)


def merge_paths_with_sources(self: PathsWithSourcesType, other: PathsWithSourcesType) \
        -> PathsWithSourcesType:
    for k, v in other.items():
        self[k] |= v
    return self


@dataclasses.dataclass
class IncludeDataWithSource(object):
    include_dirs: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)
    include_files: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)
    unresolved: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)

    def __ior__(self, other):
        merge_paths_with_sources(self.include_dirs, other.include_dirs)
        merge_paths_with_sources(self.include_files, other.include_files)
        merge_paths_with_sources(self.unresolved, other.unresolved)
        return self

    @staticmethod
    def from_dict(d, source):
        ret = IncludeDataWithSource()
        ret.include_dirs = {pathlib.Path(item): {source} for item in d["include_dirs"]}
        ret.include_files = {pathlib.Path(item): {source} for item in d["include_files"]}
        ret.unresolved = {pathlib.Path(item): {source} for item in d["unresolved"]}
        return ret


def die(*args, **kwargs) -> NoReturn:
    logging.error(*args, **kwargs)
    sys.exit(1)


def jsonify(obj):
    """Make obj valid for json.dumps."""
    if isinstance(obj, list) or isinstance(obj, set):
        return sorted([jsonify(item) for item in obj])
    if isinstance(obj, dict):
        return collections.OrderedDict(
            sorted((str(key), jsonify(value)) for key, value in obj.items()))
    return str(obj)


def endswith(a: pathlib.Path, b: pathlib.Path) -> bool:
    return len(a.parts) >= len(b.parts) and a.parts[-len(b.parts):] == b.parts


def prefix_of(a: pathlib.Path, b: pathlib.Path) -> pathlib.Path:
    if not endswith(a, b):
        die("%s does not end with %s", a, b)
    return pathlib.Path(*a.parts[:-len(b.parts)])


class Numfiles(object):
    """Lazily evaluates to the number of files """

    def __init__(self, path: pathlib.Path):
        self._path = path

    def __int__(self):
        return sum([len(files) for _, _, files in os.walk(self._path)])


@dataclasses.dataclass()
class FuzzySearchResult(object):
    additional_files: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)
    additional_includes: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)
    unknown_raw_include: Paths = dataclasses.field(default_factory=Paths)
    known_files_reversed: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)
    all_headers_reversed: PathsWithSourcesType = dataclasses.field(default_factory=PathsWithSources)

    def __ior__(self, other):
        merge_paths_with_sources(self.additional_files, other.additional_files)
        merge_paths_with_sources(self.additional_includes, other.additional_includes)
        self.unknown_raw_include |= other.unknown_raw_include
        merge_paths_with_sources(self.known_files_reversed, other.known_files_reversed)
        merge_paths_with_sources(self.all_headers_reversed, other.all_headers_reversed)
        return self


class GenDdkHeaders(buildozer_command_builder.BuildozerCommandBuilder):
    def __init__(self, include_data: IncludeDataWithSource,
                 *init_args, **init_kwargs):
        super().__init__(*init_args, **init_kwargs)
        self._debug_dump = dict()
        self._include_data = include_data

        self._calc()

    def _sanitize_keys(self, d: dict[pathlib.Path, Any]) -> dict[pathlib.Path, Any]:
        ret = dict()
        for dep, value in d.items():
            if dep.is_absolute():
                logging.debug("Unknown dep outside workspace: %s", dep)
                self._outside.add(dep)
                continue

            try:
                dep = (self._workspace_root() / dep).resolve(strict=True).relative_to(self._workspace_root())
            except FileNotFoundError:
                logging.debug("Missing dep: %s", dep)
                self._missing.add(dep)
                continue

            ret[dep] = value
        return ret

    def _calc(self):
        for k, v in vars(self._include_data).items():
            self._dump_debug(pathlib.Path("0_input", k).with_suffix(".json"), jsonify(v))

        self._outside = set()
        self._missing = set()

        self._handle_unresolved()

        self._sanitized_include_data = IncludeDataWithSource(
            include_files=self._sanitize_keys(self._include_data.include_files),
            include_dirs=self._sanitize_keys(self._include_data.include_dirs),
        )
        self._dump_debug("1_sanitized/input_sanitized.json",
                         jsonify(vars(self._sanitized_include_data)))
        self._dump_debug("1_sanitized/outside.json", jsonify(self._outside))
        self._dump_debug("1_sanitized/missing.json", jsonify(self._missing))

        if self._outside:
            strs = sorted(str(path) for path in self._outside)
            logging.error("The following are outside of repo: \n%s", "\n".join(strs))

        if self._missing:
            strs = sorted(str(path) for path in self._missing)
            logging.error("The following are missing: \n%s", "\n".join(strs))

        if (self._outside or self._missing) and not self.args.keep_going:
            die("Exiting.")

        # package -> files
        self._package_files: PathsWithSourcesType = PathsWithSources()
        for file in self._sanitized_include_data.include_files:
            package = self._get_package(file)
            if not package:
                continue
            self._package_files[package].add(file)

        self._dump_debug("2_calc/package_files.json", jsonify(self._package_files))

        # package -> include dirs
        self._package_includes: PathsWithSourcesType = PathsWithSources()
        for include in self._sanitized_include_data.include_dirs:
            package = self._get_package(include)
            if not package:
                continue
            self._package_includes[package].add(include)

        self._dump_debug("2_calc/package_includes.json", jsonify(self._package_includes))

    def _handle_unresolved(self):
        # Can't find a good way to handle these yet, so let's output an
        # error message and asks for manual intervention.

        if self._include_data.unresolved:
            logging.error("Found unresolved includes. Run with `--dump` to trace the sources.")

        for included in self._include_data.unresolved:
            logging.error("Unresolved: %s", included)

    def _create_buildozer_commands(self):
        sorted_package_files = sorted(
            (package, sorted(files)) for package, files in self._package_files.items())

        # List of all known include directories, relative to workspace root
        for package, files in sorted_package_files:
            self._generate_target(package, "all_headers_allowlist", files,
                                  self._package_includes[package],
                                  self._is_allowed)
            self._generate_target(package, "all_headers_unsafe", files,
                                  self._package_includes[package],
                                  lambda x: not self._is_allowed(x))

    def _get_package(self, directory: pathlib.Path) -> Optional[pathlib.Path]:
        dir_parts = directory.parts
        for package in self.args.package:
            if dir_parts[:len(package.parts)] == package.parts:
                return package
        return None  # ignore

    def _generate_target(self, package: pathlib.Path, name: str,
                         files: Iterable[pathlib.Path],
                         include_dirs: Iterable[pathlib.Path],
                         should_include: Callable[[pathlib.Path], bool]):
        target = self._new("ddk_headers", name, str(package))
        glob_dirs: PathsWithSourcesType = PathsWithSources()

        for file in sorted(files):
            rel_file = file.relative_to(package)

            if self._is_excluded(rel_file) or not should_include(rel_file):
                continue

            glob_dir = self._get_glob_dir_or_none(rel_file)
            if glob_dir:
                glob_dirs[glob_dir].add(rel_file)
            else:
                self._add_attr(target, "hdrs", str(rel_file), quote=True)

        for directory in include_dirs:
            rel_dir = directory.relative_to(package)
            if self._is_excluded(rel_dir) or not should_include(rel_dir):
                continue
            self._add_attr(target, "includes", rel_dir, quote=True)

        if glob_dirs:
            glob_target = self._new("filegroup", name + "_globs", str(package), load_from=None)
            # TODO make incremental; do not delete old glob patterns
            self._set_attr(glob_target, "srcs", """glob([{}])""".format(
                ",\\ ".join([repr(f"{d}/**/*.h") for d in glob_dirs])))
            self._add_attr(target, "hdrs", glob_target, quote=True)

            for glob_dir, files in glob_dirs.items():
                logging.info("%s has %d files, globbing %d files",
                             glob_dir, len(files),
                             Numfiles(self._workspace_root() / package / glob_dir))

    def _dump_debug(self, rel_path, obj):
        path = self.args.dump / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as fp:
            json.dump(obj, fp, indent=4)

    def _get_glob_dir_or_none(self, rel_file) -> Optional[pathlib.Path]:
        rel_file_parts = rel_file.parts
        for glob_dir in self.args.glob:
            if rel_file_parts[:len(glob_dir.parts)] == glob_dir.parts:
                return glob_dir
        return None

    def _analyze_include_directives(self, file) -> Optional[Paths]:
        file_path = self._workspace_root() / file

        if not file_path.is_file():
            logging.warning("Can't find %s", file_path)
            return None

        ret = set()
        with open(file_path) as fp:
            for line in fp:
                mo = re.match(_INCLUDE_DIRECTIVE, line)
                if not mo:
                    continue
                if mo.group("path1"):
                    ret.add(pathlib.Path(mo.group("path1")))
                if mo.group("path2"):
                    ret.add(pathlib.Path(mo.group("path2")))
        return ret

    @staticmethod
    def _build_reverse_lookup_table(files: Iterable[pathlib.Path]) \
            -> PathsWithSourcesType:

        ret = PathsWithSources()

        for file in files:
            for start in range(-1, -len(file.parts), -1):
                ret[pathlib.Path(*file.parts[start:])].add(file)

        return ret

def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--input", help="Input directory or file from analyze_inputs",
                        type=pathlib.Path)
    parser.add_argument("-v", "--verbose", help="verbose mode", action="store_true")
    parser.add_argument("-k", "--keep-going",
                        help="Keeps going on errors. This includes buildozer and this script.",
                        action="store_true")
    parser.add_argument("--stdout",
                        help="buildozer writes changed BUILD file to stdout (dry run)",
                        action="store_true")
    parser.add_argument("--package", nargs="*", type=pathlib.Path,
                        help="""List of known packages. If an input file is found in the known
                                package, subpackage will not be created. Only input files
                                in known packages are considered; others are silently ignored.""",
                        default=[pathlib.Path("common")])
    parser.add_argument("--allowed", nargs="*", type=pathlib.Path,
                        help="""List of paths under --package that are known to be allowed.
                                Others are placed in the unsafe list.
                                """,
                        default=[pathlib.Path(e) for e in [
                            "include",
                            "arch/arm64/include",
                            "arch/x86/include",
                        ]])
    parser.add_argument("--glob", nargs="*", type=pathlib.Path,
                        help="""List of paths under --package that should be globbed instead
                                of listing individual files.""",
                        default=[pathlib.Path(e) for e in [
                            "include",
                            "arch/arm64/include",
                            "arch/x86/include",
                        ]])
    parser.add_argument("--exclude_regex", nargs="*",
                        default=[
                            r"(^|/)arch/(?!(arm64|x86))",
                            r"^tools(/|$)",
                            r"^security(/|$)",
                            r"^net(/|$)",
                            r"^scripts(/|$)",
                        ],
                        help="""List of regex patterns that should not be added to the generated
                                Bazel targets.""")
    parser.add_argument("--dump", type=pathlib.Path,
                        help="""Directory that stores debug info.""")
    return parser.parse_args(argv)


def get_all_files_and_includes(path: pathlib.Path) -> IncludeDataWithSource:
    """Merge all from args.input, tracking the source too. Return values are un-sanitized."""
    if path.is_file():
        with open(path) as f:
            return IncludeDataWithSource.from_dict(json.load(f), path)
    if path.is_dir():
        ret = IncludeDataWithSource()
        for root, _, files in os.walk(path):
            for file in files:
                with open(pathlib.Path(root, file)) as f:
                    ret |= IncludeDataWithSource.from_dict(json.load(f), pathlib.Path(root, file))
        return ret

    die("Unknown file %s", path)


def main(argv: Sequence[str]):
    args = parse_args(argv)
    log_level = logging.INFO if args.verbose else logging.WARNING
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    include_data = get_all_files_and_includes(args.input)
    GenDdkHeaders(args=args, include_data=include_data).run()


if __name__ == "__main__":
    main(sys.argv[1:])
