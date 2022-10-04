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


# TODO make incremental; detect glob threshold on resulting list; don't add to glob
# TODO subdirs

class DdkHeadersTargetGenerator(buildozer_command_builder.BuildozerCommandBuilder):
    def __init__(self, *init_args, **init_kwargs):
        super().__init__(*init_args, **init_kwargs)
        self._input = self.args.input

    # TODO run twice
    def run(self):
        self.existing = dict()

        with self:
            self._create_buildozer_commands()
            self._run_buildozer()

    def _create_buildozer_commands(self):
        all_files = [pathlib.Path(e.strip()) for e in self._input.readlines()]

        # dir -> files
        directories: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for file in all_files:
            directories[file.parent].append(file)

        logging.info("directories = %s", directories)

        # package -> dirs
        known_packages: dict[Optional[pathlib.Path], list[pathlib.Path]] = \
            collections.defaultdict(list)
        for dir in directories:
            package = self._get_package(dir)
            known_packages[package].append(dir)

        logging.info("known_packages = %s", known_packages)

        for package, dirs in known_packages.items():
            if not package:
                continue

            for dir in dirs:
                files = directories[dir]
                self._handle_dir(package, dir, files)

    def _get_package(self, dir: pathlib.Path) -> Optional[pathlib.Path]:
        dir_parts = dir.parts
        for package in self.args.package:
            if dir_parts[:len(package.parts)] == package.parts:
                return package
        return None  # ignore

    def _handle_dir(self, package: pathlib.Path, dir: pathlib.Path, files: list[pathlib.Path]):
        name = pathlib.Path(*dir.parts[len(package.parts):])
        target = self._new("ddk_headers", str(name), str(package))
        self._add_attr(target, "includes", str(name), quote=True)
        if len(files) > self.args.glob_threshold:
            self._set_attr(target, "hdrs", f'glob(["{name}/**/*.h"])')
        else:
            for file in files:
                self._add_attr(target, "hdrs", pathlib.Path(*file.parts[len(package.parts):]),
                               quote=True)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--input", help="Input list of headers",
                        type=argparse.FileType("r"), default=sys.stdin)
    parser.add_argument("-o", "--output", help="Output shell script",
                        type=argparse.FileType("w"), default=sys.stdout)
    parser.add_argument("-v", "--verbose", help="verbose mode", action="store_true")
    parser.add_argument("-k", "--keep-going",
                        help="buildozer keeps going on errors. Use when targets are already "
                             "defined. There may be duplicated FIXME comments.",
                        action="store_true")
    parser.add_argument("--stdout",
                        help="buildozer writes changed BUILD file to stdout (dry run)",
                        action="store_true")
    parser.add_argument("--package", nargs="*", type=pathlib.Path,
                        help="""List of known packages. If an input file is found in the known
                                package, subpackage will not be created.""",
                        default=[pathlib.Path("common")])
    parser.add_argument("--glob_threshold", type=int, default=20,
                        help="""Threashold to turn list into glob""",
                        )
    return parser.parse_args(argv)


def main(argv: Sequence[str]):
    args = parse_args(argv)
    log_level = logging.INFO if args.verbose else logging.WARNING
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    DdkHeadersTargetGenerator(args=args).run()


if __name__ == "__main__":
    main(sys.argv[1:])
