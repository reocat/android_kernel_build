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
import dataclasses
import fnmatch
import logging
import pathlib
import os
import shlex
import sys
import re
from typing import TextIO, Iterable, Optional

_RE = r"^(?P<key>\S*?)\s*:=(?P<values>((\\\n| |\t)+(\S*))*)"
_SANDBOX_INDICATOR = "/execroot/__main__/"


@dataclasses.dataclass
class CmdParseData(object):
    include_dirs: list[str] = dataclasses.field(default_factory=list)
    include_files: list[str] = dataclasses.field(default_factory=list)

class AnalyzeInputs(object):


    def __init__(self, out: TextIO, dirs: list[pathlib.Path],
                 include_filters: list[str], exclude_filters: list[str],
                 raw: bool, **ignored):
        self._out = out
        self._dirs = dirs
        self._include_filters = include_filters
        self._exclude_filters = exclude_filters
        self._raw = raw

        logging.debug("raw = %s", self._raw)

        self._workspace_dir = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if not self._workspace_dir.endswith("/"):
            self._workspace_dir += "/"
        logging.debug("workspace_dir = %s", self._workspace_dir)

        self._cmd_parser = argparse.ArgumentParser()
        self._cmd_parser.add_argument("-I", action="append", default=[])
        self._cmd_parser.add_argument("-include", action="append", default=[])

        self._unresolved: set[str] = set()

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
            self._out.flush()

        if self._unresolved:
            logging.error("The following are unresolved: \n%s", "\n".join(sorted(self._unresolved)))
            sys.exit(1)

    def _get_deps(self, path: pathlib.Path) -> set[str]:
        ret: set[str] = set()

        deps = dict()
        cmds = dict()
        with open(path) as f:
            for mo in re.finditer(_RE, f.read(), re.MULTILINE):
                key = mo.group("key")
                if key.startswith("deps_"):
                    deps[key.removeprefix("deps_")] = mo.group("values")
                elif key.startswith("cmds_"):
                    cmds[key.removeprefix("cmds_")] = mo.group("values")

            for object, deps_str in deps.items():
                deps_str = deps_str.replace("\\\n", " ")
                deps = set(self._filter_deps(deps_str.split()))
                deps = self._resolve_files(deps, cmds.get(object), path)
                deps = set(self._sanitize_deps(deps))
                ret.update(deps)
        return ret

    def _filter_deps(self, deps: Iterable[str]) -> Iterable[str]:
        for dep in deps:
            dep = dep.strip()
            if not dep:
                continue
            if dep.startswith("$(wildcard") or dep.endswith(")"):
                # Ignore wildcards; we don't need them for headers analysis
                continue

            for exclude_filter in self._exclude_filters:
                if fnmatch.fnmatch(dep, exclude_filter):
                    continue

            should_include = any(fnmatch.fnmatch(dep, i) for i in self._include_filters)
            should_exclude = any(fnmatch.fnmatch(dep, i) for i in self._exclude_filters)

            if should_include and not should_exclude:
                yield dep

    def _parse_cmd(self, cmd: Optional[str]) -> CmdParseData:
        if not cmd:
            return CmdParseData()

        ret = CmdParseData()
        # Poor-man's cmd parser
        for one_cmd in cmd.split(";"):
            tokens = shlex.split(one_cmd)
            if not tokens or "clang" not in pathlib.Path(tokens[0]).name:
                continue
            known, _ = self._cmd_parser.parse_known_args(tokens[1:])
            ret.include_files += known.include
            ret.include_dirs += known.I
        return ret

    def _resolve_files(self, deps: Iterable[str], cmd: Optional[str],
                       cmd_file_path: pathlib.Path) -> Iterable[str]:
        cmd_parse_data = self._parse_cmd(cmd)

        for dep_list in (cmd_parse_data.include_files, deps):
            for dep in dep_list:
                path = pathlib.Path(dep)

                if path.is_absolute():
                    yield str(path)
                    continue

                found = False
                for include in cmd_parse_data.include_dirs:
                    include_path = include / path
                    if include_path.is_file():
                        yield str(include_path)
                        found = True
                        break

                if found:
                    continue

                logging.debug("%s: Unknown dep %s", cmd_file_path, dep)
                self._unresolved.add(dep)

    def _sanitize_deps(self, deps: Iterable[str]) -> Iterable[str]:
        for dep in deps:
            if not self._raw:
                # Trim the workspace root.
                dep = dep.removeprefix(self._workspace_dir)

                # Hack to trim the sandbox root.
                try:
                    idx = dep.index(_SANDBOX_INDICATOR)
                    dep = dep[idx + len(_SANDBOX_INDICATOR):]
                except ValueError:
                    pass

            yield dep


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
    parser.add_argument("--include_filters", nargs="*", default=["*"])
    parser.add_argument("--exclude_filters", nargs="*", default=[])

    args = parser.parse_args()
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")

    AnalyzeInputs(**vars(parser.parse_args())).run()
