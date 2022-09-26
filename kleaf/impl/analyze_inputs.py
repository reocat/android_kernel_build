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

"""Analyze the inputs from `.cmd` files"""

import absl.flags.argparse_flags
import argparse
import fnmatch
import logging
import pathlib
import os
import sys
import re
from typing import TextIO, Iterable, Optional

_RE = r"^(?P<key>\S*?)\s*:=(?P<values>((\\\n| |\t)+(\S*))*)"


class AnalyzeInputs(object):
    def __init__(self, out: TextIO, dirs: list[pathlib.Path], pattern: Optional[str]):
        self.out = out
        self.dirs = dirs
        self.pattern = pattern

    def run(self):
        result: set[str] = set()
        for dir in self.dirs:
            for root, _, files in os.walk(dir):
                root_path = pathlib.Path(root)
                for filename in files:
                    result.update(self._get_deps(root_path / filename))

        for e in sorted(result):
            self.out.write(e)
            self.out.write("\n")

    def _get_deps(self, path: pathlib.Path) -> set[str]:
        ret: set[str] = set()
        with open(path) as f:
            for mo in re.finditer(_RE, f.read(), re.MULTILINE):
                key = mo.group("key")
                if key.startswith("deps_"):
                    values = mo.group("values").replace("\\\n", " ")
                    values = set(self._sanitize_values(values.split()))
                    ret.update(values)
        return ret

    def _sanitize_values(self, values: Iterable[str]) -> Iterable[str]:
        for value in values:
            value = value.strip()
            if not value:
                continue
            if value.startswith("$(wildcard") or value.endswith(")"):
                # Ignore wildcards; we don't need them for headers analysis
                continue
            if self.pattern:
                if not fnmatch.fnmatch(value, self.pattern):
                    continue
            yield value


if __name__ == "__main__":
    # argparse_flags.ArgumentParser only accepts --flagfile if there
    # are some DEFINE'd flags
    # https://github.com/abseil/abseil-py/issues/199
    absl.flags.DEFINE_string("flagfile_hack_do_not_use", "", "")

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    parser = absl.flags.argparse_flags.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=argparse.FileType("w"), default=sys.stdout)
    parser.add_argument("--dirs", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--pattern")

    AnalyzeInputs(**vars(parser.parse_args())).run()
