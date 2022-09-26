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
import argparse
import dataclasses
import fnmatch
import logging
import pathlib
import os
import shlex
import sys
import re
import tarfile
from typing import TextIO, Iterable, Optional

_RE = r"^(?P<key>\S*?)\s*:=(?P<values>((\\\n| |\t)+(\S*))*)"


@dataclasses.dataclass
class CmdParseData(object):
    include_dirs: list[pathlib.Path] = dataclasses.field(default_factory=list)
    include_files: list[pathlib.Path] = dataclasses.field(default_factory=list)


class AnalyzeInputs(object):

    def __init__(self, out: TextIO, dirs: list[pathlib.Path],
                 include_filters: list[str], exclude_filters: list[str],
                 raw: bool, input_archives: list[tarfile.TarFile], **ignored):
        self._out = out
        self._dirs = dirs
        self._include_filters = include_filters
        self._exclude_filters = exclude_filters
        self._unresolved: set[pathlib.Path] = set()
        self._outside: set[pathlib.Path] = set()
        self._missing: set[pathlib.Path] = set()
        self._raw = raw

        logging.debug("raw = %s", self._raw)

        self._workspace_dir = pathlib.Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
        logging.debug("workspace_dir = %s", self._workspace_dir)

        self._cmd_parser = argparse.ArgumentParser()
        self._cmd_parser.add_argument("-I", type=pathlib.Path, action="append", default=[])
        self._cmd_parser.add_argument("-include", type=pathlib.Path, action="append", default=[])
        self._cmd_parser.add_argument("--sysroot", type=pathlib.Path)

        self._archived_input_names: set[pathlib.Path] = set()
        for archive in input_archives:
            names = archive.getnames()
            paths = set(pathlib.Path(os.path.normpath(name)) for name in names)
            self._archived_input_names.update(paths)

    def run(self):
        result: set[pathlib.Path] = set()
        for dir in self._dirs:
            for root, _, files in os.walk(dir):
                root_path = pathlib.Path(root)
                for filename in files:
                    result.update(self._get_deps(root_path / filename))

        for e in sorted(result):
            self._out.write(str(e))
            self._out.write("\n")
            self._out.flush()

        bad = {
            "unresolved": self._unresolved,
            "outside of repo": self._outside,
            "missing": self._missing,
        }

        for msg, paths in bad.items():
            if paths:
                strs = sorted(str(path) for path in paths)
                logging.error("The following are %s: \n%s", msg, "\n".join(strs))

        if any(bad.values()):
            sys.exit(1)

    def _get_deps(self, path: pathlib.Path) -> set[pathlib.Path]:
        ret: set[pathlib.Path] = set()

        deps = dict()
        cmds = dict()
        with open(path) as f:
            for mo in re.finditer(_RE, f.read(), re.MULTILINE):
                key = mo.group("key")
                if key.startswith("deps_"):
                    deps[key.removeprefix("deps_")] = mo.group("values")
                elif key.startswith("cmd_"):
                    cmds[key.removeprefix("cmd_")] = mo.group("values")

            for object, deps_str in deps.items():
                deps_str = deps_str.replace("\\\n", " ")
                one_deps = set(self._filter_deps(deps_str.split()))
                one_deps = self._resolve_files(one_deps, cmds.get(object), path)
                one_deps = set(self._sanitize_deps(one_deps))
                ret.update(one_deps)
        return ret

    def _filter_deps(self, dep_strs: Iterable[str]) -> Iterable[pathlib.Path]:
        for dep_str in dep_strs:
            dep_str = dep_str.strip()
            if not dep_str:
                continue
            if dep_str.startswith("$(wildcard") or dep_str.endswith(")"):
                # Ignore wildcards; we don't need them for headers analysis
                continue

            for exclude_filter in self._exclude_filters:
                if fnmatch.fnmatch(dep_str, exclude_filter):
                    continue

            should_include = any(fnmatch.fnmatch(dep_str, i) for i in self._include_filters)
            should_exclude = any(fnmatch.fnmatch(dep_str, i) for i in self._exclude_filters)

            if should_include and not should_exclude:
                yield pathlib.Path(dep_str)

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
            if known.sysroot:
                ret.include_dirs.append(known.sysroot)
        return ret

    def _resolve_files(self, deps: Iterable[pathlib.Path], cmd: Optional[str],
                       cmd_file_path: pathlib.Path) -> Iterable[pathlib.Path]:
        cmd_parse_data = self._parse_cmd(cmd)

        for dep_list in (cmd_parse_data.include_files, deps):
            for dep in dep_list:
                # Pass through absolute paths.
                # They might be in the sandbox, so don't check for existence.
                if dep.is_absolute():
                    yield dep
                    continue

                found = False
                for include in cmd_parse_data.include_dirs:
                    include_path = include / dep
                    if include_path.is_file():
                        yield include_path.resolve()
                        found = True
                        break

                if found:
                    continue

                # Ignore headers in given archives
                if dep in self._archived_input_names:
                    continue

                logging.debug("%s: Unknown dep %s", cmd_file_path, dep)
                self._unresolved.add(dep)

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
    parser.add_argument("--out", type=argparse.FileType("w"), default=sys.stdout)
    parser.add_argument("--dirs", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--raw", action="store_true", default=False)
    parser.add_argument("-v", "--verbose", action="store_true", default=False)
    parser.add_argument("--include_filters", nargs="*", default=["*"])
    parser.add_argument("--exclude_filters", nargs="*", default=[])
    parser.add_argument("--input_archives", type=tarfile.open, nargs="*", default=[])

    args = parser.parse_args()
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")

    AnalyzeInputs(**vars(parser.parse_args())).run()
