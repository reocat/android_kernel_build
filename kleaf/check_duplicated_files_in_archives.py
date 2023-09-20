#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import collections
import pathlib
import os


def _sanitize(line: str) -> str:
    line = line.strip()
    # If the command to create the archive was
    #   tar cvf foo.tar.gz -C directory .
    # then lines may start with "./". Resolve them properly.
    return str(pathlib.PurePosixPath(line))


def _list_entries(list_file: pathlib.Path) -> list[str]:
    with open(list_file) as f:
        return [_sanitize(name) for name in f if not name.strip().endswith("/")]


def main(list_files_dir: pathlib.Path) -> None:
    """Checks that when extracting each archive to the same directory, files won't
    be overwritten.

    This is a semi-replacement of the -k option in GNU tar.
    """
    reverse_dict: dict[str, list[str]] = collections.defaultdict(list)

    for root, _, files in os.walk(list_files_dir):
        for file in files:
            list_file = pathlib.Path(root) / file
            for entry in _list_entries(list_file):
                src_archive = str(list_file.relative_to(
                    list_files_dir)).removesuffix(".log")
                reverse_dict[entry].append(src_archive)

    duplicated = {f: f_archives for f, f_archives in reverse_dict.items() if
                  len(f_archives) > 1}
    if duplicated:
        def fn(f, f_archives): return (
            f"File {str(f)} appeared in {len(f_archives)} archives:\n  " +
            "\n  ".join(str(archive) for archive in f_archives))
        msg = "\n".join(fn(f, f_archives)
                        for f, f_archives in duplicated.items())
        raise Exception(f"Multiple archives contain the same files.\n{msg}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=main.__doc__)
    parser.add_argument("list_files_dir", type=pathlib.Path,
                        help="Directory of text files containing list of entries to check")
    args = parser.parse_args()
    main(**vars(args))
