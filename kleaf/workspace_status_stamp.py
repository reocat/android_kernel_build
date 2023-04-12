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
import shutil
import subprocess
import sys
import xml.dom.minidom
import xml.parsers.expat
from typing import Optional


@dataclasses.dataclass
class PathCollectible(object):
    path: str

    def collect(self):
        return NotImplementedError


@dataclasses.dataclass
class PathPopen(PathCollectible):
    popen: subprocess.Popen

    def collect(self):
        return collect(self.popen)


@dataclasses.dataclass
class PresetResult(PathCollectible):
    result: str

    def collect(self):
        return self.result


def call_setlocalversion(bin, srctree, *args) \
        -> Optional[subprocess.Popen[str]]:
    """Call setlocalversion.

    Args:
      bin: path to setlocalversion, or None if it does not exist.
      srctree: The argument to setlocalversion.
      args: additional arguments
    Return:
      A subprocess.Popen object, or None if bin or srctree does not exist.
    """
    working_dir = "build/kernel/kleaf/workspace_status_dir"
    if bin and os.path.isdir(srctree):
        return subprocess.Popen([bin, srctree] + list(args),
                                text=True,
                                stdout=subprocess.PIPE,
                                cwd=working_dir)
    return None


def list_projects():
    """Call `repo manifest -r` and returns a mapping from projects to revisions.
    """
    try:
        manifest = subprocess.check_output(["repo", "manifest", "-r"],
                                           text=True)
    except subprocess.SubprocessError as e:
        logging.error("Unable to execute repo manifest -r: %s", e)
        return {}
    try:
        dom = xml.dom.minidom.parseString(manifest)
    except xml.parsers.expat.ExpatError as e:
        logging.error("Unable to parse repo manifest: %s", e)
        return {}
    projects = dom.documentElement.getElementsByTagName("project")
    return {
        proj.getAttribute("path"): proj.getAttribute("revision")
        for proj in projects
    }


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
        self.init_for_dot_source_date_epoch_dir()
        self.projects = list_projects()

    def init_for_dot_source_date_epoch_dir(self) -> None:
        self.kernel_dir = os.path.realpath(".source_date_epoch_dir")
        if not os.path.isdir(self.kernel_dir):
            self.kernel_dir = None
        if self.kernel_dir:
            self.kernel_rel = os.path.relpath(self.kernel_dir)

        self.find_setlocalversion()

    def main(self) -> int:
        scmversion_map = self.call_setlocalversion_all()
        scmversion_new_map = self.get_scmversion_from_repo_manifest()

        source_date_epoch_map = self.async_get_source_date_epoch_kernel_dir()

        scmversion_result_map = self.collect_map(
            legacy_map=scmversion_map,
            new_map=scmversion_new_map,
            legacy_method="setlocalversion",
            new_method="repo manifest")

        source_date_epoch_result_map = self.collect_map(source_date_epoch_map)

        self.print_result(
            scmversion_result_map=scmversion_result_map,
            source_date_epoch_result_map=source_date_epoch_result_map,
        )
        return 0

    def find_setlocalversion(self) -> None:
        if not self.kernel_dir:
            self.setlocalversion = None
            return
        self.setlocalversion = os.path.join(self.kernel_dir,
                                            "scripts/setlocalversion")
        if not os.access(self.setlocalversion, os.X_OK):
            self.setlocalversion = None

    def call_setlocalversion_all(self) -> dict[str, PathCollectible]:
        kernel_dir_scmversion_obj = self.call_setlocalversion_kernel_dir()

        ext_modules = self.get_ext_modules()
        ext_mod_scmversion_objs = self.call_setlocalversion_ext_modules(
            ext_modules)

        scmversion_objs = list(ext_mod_scmversion_objs)
        if kernel_dir_scmversion_obj:
            scmversion_objs.append(kernel_dir_scmversion_obj)

        scmversion_map = {obj.path: obj for obj in scmversion_objs}

        return scmversion_map

    def call_setlocalversion_kernel_dir(self) -> Optional[PathCollectible]:
        if not self.setlocalversion or not self.kernel_dir:
            return None

        return PathPopen(
            self.kernel_rel,
            call_setlocalversion(self.setlocalversion, self.kernel_dir))

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

    def call_setlocalversion_ext_modules(self, ext_modules) \
            -> list[PathCollectible]:
        if not self.setlocalversion:
            return []

        ret = []
        for ext_mod in ext_modules:
            popen = call_setlocalversion(self.setlocalversion,
                                         os.path.realpath(ext_mod))
            ret.append(PathPopen(ext_mod, popen))
        return ret

    def get_scmversion_from_repo_manifest(self):
        # FIXME prefix patch numbers
        # FIXME suffix -dirty
        # FIXME BUILD_NUMBER
        return {
            proj: PresetResult(proj, "-g{}".format(revision[:12]))
            for proj, revision in self.projects.items()
        }

    def async_get_source_date_epoch_kernel_dir(self) \
            -> dict[str, PathCollectible]:
        env_val = os.environ.get("SOURCE_DATE_EPOCH")
        if env_val:
            return {self.kernel_rel: PresetResult(self.kernel_rel, env_val)}
        if self.kernel_dir and shutil.which("git"):
            popen = subprocess.Popen(
                ["git", "-C", self.kernel_dir, "log", "-1", "--pretty=%ct"],
                text=True,
                stdout=subprocess.PIPE)
            return {self.kernel_rel: PathPopen(self.kernel_rel, popen)}
        return {self.kernel_rel: PresetResult(self.kernel_rel, "0")}

    def collect_map(
        self,
        legacy_map: dict[str, PathCollectible],
        new_map: Optional[dict[str, PathCollectible]] = None,
        legacy_method: Optional[str] = None,
        new_method: Optional[str] = None,
    ) -> dict[str, str]:
        legacy_results = {
            path: path_popen.collect()
            for path, path_popen in legacy_map.items()
        }

        if not new_map:
            return legacy_results

        new_results = {
            path: path_popen.collect()
            for path, path_popen in new_map.items()
        }
        all_results = dict(legacy_results)

        for path, new_result in new_results.items():
            if path in legacy_results and legacy_results[path] != new_result:
                logging.warning(
                    "For project %s, %s gives %s, but "
                    "%s gives %s. "
                    "This will be a problem when you delete the "
                    "top-level build.config or "
                    ".source_date_epoch_dir", path, legacy_method,
                    legacy_results[path], new_method, new_result)
                continue
            all_results[path] = new_result

        return all_results

    def print_result(
        self,
        scmversion_result_map,
        source_date_epoch_result_map,
    ) -> None:
        stable_source_date_epochs = " ".join(
            "{}:{}".format(path, result)
            for path, result in source_date_epoch_result_map.items())
        print("STABLE_SOURCE_DATE_EPOCHS", stable_source_date_epochs)

        # If the list is empty, this prints "STABLE_SCMVERSIONS", and is
        # filtered by Bazel.
        stable_scmversions = " ".join(
            "{}:{}".format(path, result)
            for path, result in scmversion_result_map.items())
        print("STABLE_SCMVERSIONS", stable_scmversions)


if __name__ == '__main__':
    logging.basicConfig(stream=sys.stderr,
                        level=logging.WARNING,
                        format="%(levelname)s: %(message)s")
    sys.exit(Stamp().main())
