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
import collections
import logging
import os
import pathlib
import sys
from typing import Sequence, Optional

from build.kernel.kleaf import buildozer_command_builder


def die(*args, **kwargs):
    logging.error(*args, **kwargs)
    sys.exit(1)


class Numfiles(object):
    """Lazily evaluates to the number of files """
    def __init__(self, path: pathlib.Path):
        self._path = path

    def __int__(self):
        return sum([len(files) for _, _, files in os.walk(self._path)])

class GenDdkHeaders(buildozer_command_builder.BuildozerCommandBuilder):
    def __init__(self, *init_args, **init_kwargs):
        super().__init__(*init_args, **init_kwargs)
        self._all_files = [pathlib.Path(e.strip()) for e in self.args.input.readlines()]

    def _create_buildozer_commands(self):
        # package -> files
        package_files: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for file in self._all_files:
            package = self._get_package(file)
            if not package:
                continue
            package_files[package].append(file)

        for package, files in sorted(package_files.items()):
            self._generate_target(package, "all_headers", files)

    def _get_package(self, dir: pathlib.Path) -> Optional[pathlib.Path]:
        dir_parts = dir.parts
        for package in self.args.package:
            if dir_parts[:len(package.parts)] == package.parts:
                return package
        return None  # ignore

    def _generate_target(self, package: pathlib.Path, name: str,
                         files: list[pathlib.Path]):
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

    def _get_glob_dir_or_none(self, rel_file) -> Optional[pathlib.Path]:
        rel_file_parts = rel_file.parts
        for glob_dir in self.args.glob:
            if rel_file_parts[:len(glob_dir.parts)] == glob_dir.parts:
                return glob_dir
        return None

def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--input", help="Input list of headers",
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
