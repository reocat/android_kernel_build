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
        self._all_files = [pathlib.Path(e.strip()) for e in self.args.input.readlines()]

    def _create_buildozer_commands(self):
        # dir -> files
        directories: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for file in self._all_files:
            directories[file.parent].append(file)

        logging.info("directories = %s", "\n".join(f"{k}: {v}" for k, v in directories.items()))

        # dir -> direct_subdirs
        direct_subdirs: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for dir in directories:
            direct_subdirs[dir.parent].append(dir)

        logging.info("direct_subdirs = %s",
                     "\n".join(f"{k}: {v}" for k, v in direct_subdirs.items()))

        # package -> dirs
        known_packages: dict[pathlib.Path, list[pathlib.Path]] = collections.defaultdict(list)
        for dir in directories:
            package = self._get_package(dir)
            if not package:
                continue
            known_packages[package].append(dir)

        logging.info("known_packages = %s",
                     "\n".join(f"{k}: {v}" for k, v in known_packages.items()))

        for package, dirs in sorted(known_packages.items()):
            for dir in dirs:
                files = directories[dir]
                self._handle_dir(package, dir, files, direct_subdirs.get(dir, []))

    def _get_package(self, dir: pathlib.Path) -> Optional[pathlib.Path]:
        dir_parts = dir.parts
        for package in self.args.package:
            if dir_parts[:len(package.parts)] == package.parts:
                return package
        return None  # ignore

    def _handle_dir(self, package: pathlib.Path, dir: pathlib.Path,
                    files: list[pathlib.Path], direct_subdirs: list[pathlib.Path]):
        name = pathlib.Path(*dir.parts[len(package.parts):])
        target = self._new("ddk_headers", str(name), str(package))
        self._add_attr(target, "visibility", "//visibility:public", quote=True)
        self._add_attr(target, "includes", ".", quote=True)
        for file in sorted(files):
            self._add_attr(target, "hdrs",
                           str(pathlib.Path(*file.parts[len(package.parts):])),
                           quote=True)

        logging.info("%s subdirs: %s", dir, direct_subdirs)

        for subdir in sorted(direct_subdirs):
            self._add_attr(target, "hdrs",
                           ":" + str(pathlib.Path(*subdir.parts[len(package.parts):])),
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
    return parser.parse_args(argv)


def main(argv: Sequence[str]):
    args = parse_args(argv)
    log_level = logging.INFO if args.verbose else logging.WARNING
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    DdkHeadersTargetGenerator(args=args).run()


if __name__ == "__main__":
    main(sys.argv[1:])
