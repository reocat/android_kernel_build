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

"""Sanitize the inputs from analyze_inputs.py.

Strips out the workspace root and sandbox exec root.

This script must be executed with `bazel run`, or by providing the
root of the workspace via the --workspace parameter.
"""
import argparse
import logging
import pathlib
import os
import sys
from typing import TextIO, Iterable, Optional


class SanitizeInputs(object):
    def __init__(self, input: TextIO, output: TextIO,
                 raw: bool, workspace: Optional[pathlib.Path], **ignored):
        self._input = input
        self._output = output
        self._raw = raw
        self._outside: set[pathlib.Path] = set()
        self._missing: set[pathlib.Path] = set()

        logging.debug("raw = %s", self._raw)

        self._workspace_dir = workspace
        if not self._workspace_dir:
            self._workspace_dir = pathlib.Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
        if not self._workspace_dir:
            logging.error("Please specify --workspace.")
            sys.exit(1)
        logging.debug("workspace_dir = %s", self._workspace_dir)

    def run(self):
        items = set(pathlib.Path(e) for e in self._input.read().splitlines())
        result = set(self._sanitize_deps(items))

        for e in sorted(result):
            self._output.write(str(e))
            self._output.write("\n")
            self._output.flush()

        bad = {
            "outside of repo": self._outside,
            "missing": self._missing,
        }

        for msg, paths in bad.items():
            if paths:
                strs = sorted(str(path) for path in paths)
                logging.error("The following are %s: \n%s", msg, "\n".join(strs))

        if any(bad.values()):
            sys.exit(1)

    def _sanitize_deps(self, deps: Iterable[pathlib.Path]) -> Iterable[pathlib.Path]:
        for dep in deps:
            if not self._raw:
                # Hack to trim the sandbox root; strip everything before and including __main__/
                parts = dep.parts
                if "sandbox" in parts:
                    try:
                        idx = parts.index("__main__")
                        dep = pathlib.Path(*parts[idx + 1:])
                    except ValueError:
                        pass

                # Trim the workspace root.
                if dep.is_absolute():
                    if dep.parts[:len(self._workspace_dir.parts)] == self._workspace_dir.parts:
                        dep = dep.relative_to(self._workspace_dir)

                if dep.is_absolute():
                    logging.debug("Unknown dep outside workspace: %s", dep)
                    self._outside.add(dep)
                    continue

                try:
                    dep = (self._workspace_dir / dep).resolve().relative_to(self._workspace_dir)
                except FileNotFoundError:
                    logging.debug("Missing dep: %s", dep)
                    self._missing.add(dep)
                    continue

            yield dep


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=argparse.FileType("r"), default=sys.stdin)
    parser.add_argument("--output", type=argparse.FileType("w"), default=sys.stdout)
    parser.add_argument("--raw", action="store_true", default=False)
    parser.add_argument("--workspace", type=pathlib.Path, default=None)
    parser.add_argument("-v", "--verbose", action="store_true", default=False)

    args = parser.parse_args()
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")

    SanitizeInputs(**vars(parser.parse_args())).run()
