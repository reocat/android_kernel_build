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
import pathlib
import sys
from typing import Sequence, Optional

from build.kernel.kleaf import buildozer_command_builder


def die(*args, **kwargs):
    logging.error(*args, **kwargs)
    sys.exit(1)


class DdkHeadersTargetGenerator(buildozer_command_builder.BuildozerCommandBuilder):
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
        for file in sorted(files):
            self._add_attr(target, "hdrs",
                           str(pathlib.Path(*file.parts[len(package.parts):])),
                           quote=True)
            try:
                idx = file.parent.parts.index("include")
                include_dirs.add(pathlib.Path(*file.parent.parts[:idx]))
            except ValueError:
                pass
        for dir in include_dirs:
            self._add_attr(target, "includes", dir, quote=True)


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
    return parser.parse_args(argv)


def main(argv: Sequence[str]):
    args = parse_args(argv)
    log_level = logging.INFO if args.verbose else logging.WARNING
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    DdkHeadersTargetGenerator(args=args).run()


if __name__ == "__main__":
    main(sys.argv[1:])
