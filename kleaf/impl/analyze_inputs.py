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
_SANDBOX_INDICATOR = "/execroot/__main__/"


class AnalyzeInputs(object):
    def __init__(self, out: TextIO, dirs: list[pathlib.Path],
                 pattern: Optional[str], raw: bool, **ignored):
        self._out = out
        self._dirs = dirs
        self._pattern = pattern
        self._raw = raw

        logging.debug("raw = %s", self._raw)

        self._workspace_dir = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if not self._workspace_dir.endswith("/"):
            self._workspace_dir += "/"
        logging.debug("workspace_dir = %s", self._workspace_dir)

    def run(self):
        result: set[str] = set()
        for dir in self._dirs:
            for root, _, files in os.walk(dir):
                root_path = pathlib.Path(root)
                for filename in files:
                    result.update(self._get_deps(root_path / filename))

        for e in sorted(result):
            self._out.write(e)
            self._out.write("\n")

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
            if self._pattern:
                if not fnmatch.fnmatch(value, self._pattern):
                    continue

            if not self._raw:
                # Trim the workspace root.
                value = value.removeprefix(self._workspace_dir)

                # Hack to trim the sandbox root.
                try:
                    idx = value.index(_SANDBOX_INDICATOR)
                    value = value[idx + len(_SANDBOX_INDICATOR):]
                except ValueError:
                    pass

            yield value


if __name__ == "__main__":
    # argparse_flags.ArgumentParser only accepts --flagfile if there
    # are some DEFINE'd flags
    # https://github.com/abseil/abseil-py/issues/199
    absl.flags.DEFINE_string("flagfile_hack_do_not_use", "", "")

    parser = absl.flags.argparse_flags.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=argparse.FileType("w"), default=sys.stdout)
    parser.add_argument("--dirs", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--raw", action="store_true", default=False)
    parser.add_argument("-v", "--verbose", action="store_true", default=False)
    parser.add_argument("--pattern")

    args = parser.parse_args()
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")

    AnalyzeInputs(**vars(parser.parse_args())).run()
