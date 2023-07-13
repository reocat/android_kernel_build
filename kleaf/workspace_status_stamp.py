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

import dataclasses
import logging
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import xml.dom.minidom
import xml.parsers.expat
from typing import Optional

_FAKE_KERNEL_VERSION = "99.99.99"


@dataclasses.dataclass
class PathCollectible(object):
    """Represents a path and the result of an asynchronous task."""
    path: str

    def collect(self) -> str:
        return NotImplementedError


@dataclasses.dataclass
class PathPopen(PathCollectible):
    """Consists of a path and the result of a subprocess."""
    popen: subprocess.Popen

    def collect(self) -> str:
        return collect(self.popen)


@dataclasses.dataclass
class PresetResult(PathCollectible):
    """Consists of a path and a pre-defined result."""
    result: str

    def collect(self) -> str:
        return self.result


@dataclasses.dataclass
class LocalversionResult(PathPopen):
    """Consists of results of localversion."""
    removed_prefix: str
    suffix: Optional[str]

    def collect(self) -> str:
        ret = super().collect()
        ret = ret.removeprefix(self.removed_prefix)
        if self.suffix:
            ret += self.suffix
        return ret


def get_localversion(bin: Optional[str], project: str, *args) \
        -> Optional[PathCollectible]:
    """Call setlocalversion.

    Args:
      bin: path to setlocalversion, or None if it does not exist.
      project: relative path to the project
      args: additional arguments
    Return:
      A PathCollectible object that resolves to the result, or None if bin or
      project does not exist.
    """
    if not os.path.isdir(project):
        return None
    srctree = os.path.realpath(project)

    if bin:
        working_dir = "build/kernel/kleaf/workspace_status_dir"
        env = dict(os.environ)
        env["KERNELVERSION"] = _FAKE_KERNEL_VERSION
        env.pop("BUILD_NUMBER", None)
        popen = subprocess.Popen([bin, srctree] + list(args),
                                 text=True,
                                 stdout=subprocess.PIPE,
                                 cwd=working_dir,
                                 env=env)

        suffix = None
        if os.environ.get("BUILD_NUMBER"):
            suffix = "-ab" + os.environ["BUILD_NUMBER"]
        return LocalversionResult(
            path=project,
            popen=popen,
            removed_prefix=_FAKE_KERNEL_VERSION,
            suffix=suffix
        )

    return None


def list_projects() -> dict[str, str]:
    """Lists projects in the repository.

    Returns:
        a dictionary, where keys are paths to projects in the repository,
        and values are the localversion.
    """
    if "KLEAF_REPO_MANIFEST" in os.environ:
        with open(os.environ["KLEAF_REPO_MANIFEST"]) as repo_prop_file:
            return parse_repo_manifest(repo_prop_file.read())

    try:
        each_project_command = """
            printf '%s:' "$PWD"
            if head=$(git rev-parse --verify HEAD 2>/dev/null); then
                printf '%s%s' -g "$(echo $head | cut -c1-12)"
            fi
            if {
                git --no-optional-locks status -uno --porcelain 2>/dev/null ||
                git diff-index --name-only HEAD
            } | read dummy; then
                printf '%s' -dirty
            fi
        """
        args = ["repo", "forall", "-c", each_project_command]
        output = subprocess.check_output(
            args, text=True)
        return parse_repo_list(output)
    except (subprocess.SubprocessError, FileNotFoundError) as e:
        logging.warning(
            "Unable to execute `%s`: %s",
            " ".join([shlex.quote(arg) for arg in args]),
            e)
        return {}


def parse_repo_manifest(manifest: str) -> dict[str, str]:
    """Parses a repo manifest file.

    Returns:
        a dictionary, where keys are paths to projects in the repository,
        and values are the localversion.
    """
    try:
        dom = xml.dom.minidom.parseString(manifest)
    except xml.parsers.expat.ExpatError as e:
        logging.error("Unable to parse repo manifest: %s", e)
        return {}
    projects = dom.documentElement.getElementsByTagName("project")
    # https://gerrit.googlesource.com/git-repo/+/master/docs/manifest-format.md#element-project
    ret = {}
    for proj in projects:
        path = proj.getAttribute("path") or proj.getAttribute("name")
        revision = proj.getAttribute("revision")
        ret[path] = "-g{revision[:12]}"
    return ret


def parse_repo_list(repo_list: str) -> dict[str, str]:
    """Parses the result of the command that lists projects.

    Returns:
        a dictionary, where keys are paths to projects in the repository,
        and values are the localversion.
    """
    workspace = pathlib.Path(".").absolute()
    paths = {}
    for line in repo_list.splitlines():
        line = line.strip()
        if not line or ":" not in line:
            continue
        path, revision = line.split(":", 2)
        path = pathlib.Path(path.strip())
        revision = revision.strip()
        if path.is_relative_to(workspace):
            paths[str(path.relative_to(workspace))] = revision
        else:
            logging.info(
                "Ignoring project %s because it is not under the Bazel workspace",
                path)
    return paths


def collect(popen_obj: subprocess.Popen) -> str:
    """Collect the result of a Popen object.

    Terminates the program if return code is non-zero.

    Return:
      stdout of the subprocess.
    """
    stdout, _ = popen_obj.communicate()
    if popen_obj.returncode != 0:
        logging.error("return code is %d", popen_obj.returncode)
        sys.exit(1)
    return stdout.strip()


class Stamp(object):

    def __init__(self):
        self.ignore_missing_projects = os.environ.get(
            "KLEAF_IGNORE_MISSING_PROJECTS", "false") == "true"
        self.projects = list_projects()
        self.init_for_dot_source_date_epoch_dir()

    def init_for_dot_source_date_epoch_dir(self) -> None:
        self.kernel_dir = os.path.realpath(".source_date_epoch_dir")
        if not os.path.isdir(self.kernel_dir):
            self.kernel_dir = None
        if self.kernel_dir:
            self.kernel_rel = os.path.relpath(self.kernel_dir)

        self.find_setlocalversion()

    def main(self) -> int:
        scmversion_map = self.get_localversion_all()

        source_date_epoch_map = self.async_get_source_date_epoch_all()

        scmversion_result_map = self.collect_map(scmversion_map)

        source_date_epoch_result_map = self.collect_map(source_date_epoch_map)

        self.print_result(
            scmversion_result_map=scmversion_result_map,
            source_date_epoch_result_map=source_date_epoch_result_map,
        )
        return 0

    def find_setlocalversion(self) -> None:
        self.setlocalversion = None

        all_projects = []
        if self.kernel_dir:
            all_projects.append(self.kernel_rel)
        all_projects.extend(self.projects.keys())

        if self.ignore_missing_projects:
            all_projects = filter(os.path.isdir, all_projects)

        for proj in all_projects:
            if not os.path.isdir(proj):
                logging.error(
                    "Project %s in repo manifest does not exist on disk.",
                    proj
                )
                sys.exit(1)

            candidate = os.path.join(proj, "scripts/setlocalversion")
            if os.access(candidate, os.X_OK):
                self.setlocalversion = os.path.realpath(candidate)
                return

    def get_localversion_all(self) -> dict[str, PathCollectible]:
        all_projects = set()
        if self.kernel_dir:
            all_projects.add(self.kernel_rel)
        all_projects |= set(self.get_ext_modules())
        all_projects |= self.projects.keys()

        if self.ignore_missing_projects:
            all_projects = filter(os.path.isdir, all_projects)

        scmversion_map = {}
        for project in all_projects:
            if not os.path.isdir(project):
                logging.error(
                    "Project %s in repo manifest does not exist on disk.",
                    project)
                sys.exit(1)

            path_popen = get_localversion(self.setlocalversion, project)
            if path_popen:
                scmversion_map[project] = path_popen

        return scmversion_map

    def get_ext_modules(self) -> list[str]:
        if not self.setlocalversion:
            return []
        try:
            cmd = """
                    source build/build_utils.sh
                    source build/_setup_env.sh
                    echo $EXT_MODULES
                  """
            return subprocess.check_output(cmd,
                                           shell=True,
                                           text=True,
                                           stderr=subprocess.PIPE,
                                           executable="/bin/bash").split()
        except subprocess.CalledProcessError as e:
            logging.warning(
                "Unable to determine EXT_MODULES; scmversion "
                "for external modules may be incorrect. "
                "code=%d, stderr=%s", e.returncode, e.stderr.strip())
        return []

    def async_get_source_date_epoch_all(self) \
            -> dict[str, PathCollectible]:

        all_projects = set()
        if self.kernel_dir:
            all_projects.add(self.kernel_rel)
        all_projects |= self.projects.keys()

        if self.ignore_missing_projects:
            all_projects = filter(os.path.isdir, all_projects)

        return {
            proj: self.async_get_source_date_epoch(proj)
            for proj in all_projects
        }

    def async_get_source_date_epoch(self, rel_path) -> PathCollectible:
        env_val = os.environ.get("SOURCE_DATE_EPOCH")
        if env_val:
            return PresetResult(rel_path, env_val)
        if shutil.which("git"):
            args = [
                "git", "-C",
                os.path.realpath(rel_path), "log", "-1", "--pretty=%ct"
            ]
            popen = subprocess.Popen(args, text=True, stdout=subprocess.PIPE)
            return PathPopen(rel_path, popen)
        return PresetResult(rel_path, "0")

    def collect_map(
        self,
        legacy_map: dict[str, PathCollectible],
    ) -> dict[str, str]:
        return {
            path: path_popen.collect()
            for path, path_popen in legacy_map.items()
        }

    def print_result(
        self,
        scmversion_result_map,
        source_date_epoch_result_map,
    ) -> None:
        stable_source_date_epochs = " ".join(
            "{}:{}".format(path, result)
            for path, result in sorted(source_date_epoch_result_map.items()))
        print("STABLE_SOURCE_DATE_EPOCHS", stable_source_date_epochs)

        # If the list is empty, this prints "STABLE_SCMVERSIONS", and is
        # filtered by Bazel.
        stable_scmversions = " ".join(
            "{}:{}".format(path, result)
            for path, result in sorted(scmversion_result_map.items()))
        print("STABLE_SCMVERSIONS", stable_scmversions)


if __name__ == '__main__':
    logging.basicConfig(stream=sys.stderr,
                        level=logging.WARNING,
                        format="%(levelname)s: %(message)s")
    sys.exit(Stamp().main())
