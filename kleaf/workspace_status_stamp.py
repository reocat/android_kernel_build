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
import os
import shutil
import subprocess
import sys


@dataclasses.dataclass
class PathPopen(object):
    path: str
    popen: subprocess.Popen

    def collect(self):
        return "{}:{}".format(self.path, collect(self.popen))


@dataclasses.dataclass
class PresetResult(object):
    path: str
    result: str

    def collect(self):
        return "{}:{}".format(self.path, self.result)


def call_setlocalversion(bin, srctree, *args):
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


def collect(popen_obj):
    """Collect the result of a Popen object.

    Terminates the program if return code is non-zero.

    Return:
      stdout of the subprocess.
    """
    stdout, _ = popen_obj.communicate()
    if popen_obj.returncode != 0:
        sys.stderr.write("ERROR: return code is {}\n".format(
            popen_obj.returncode))
        sys.exit(1)
    return stdout.strip()


class Stamp(object):

    def __init__(self):
        self.init_for_dot_source_date_epoch_dir()

    def init_for_dot_source_date_epoch_dir(self):
        self.kernel_dir = os.path.realpath(".source_date_epoch_dir")
        if not os.path.isdir(self.kernel_dir):
            self.kernel_dir = None
        if self.kernel_dir:
            self.kernel_rel = os.path.relpath(self.kernel_dir)

        self.find_setlocalversion()

    def main(self):
        scmversion_map = self.call_setlocalversion_all()

        source_date_epoch_map = self.async_get_source_date_epoch_kernel_dir()

        self.print_result(
            scmversion_objs=scmversion_map.values(),
            source_date_epoch_objs=source_date_epoch_map.values(),
        )
        return 0

    def find_setlocalversion(self):
        if not self.kernel_dir:
            self.setlocalversion = None
            return
        self.setlocalversion = os.path.join(self.kernel_dir,
                                            "scripts/setlocalversion")
        if not os.access(self.setlocalversion, os.X_OK):
            self.setlocalversion = None

    def call_setlocalversion_all(self):
        kernel_dir_scmversion_obj = self.call_setlocalversion_kernel_dir()

        ext_modules = self.get_ext_modules()
        ext_mod_scmversion_objs = self.call_setlocalversion_ext_modules(
            ext_modules)

        scmversion_objs = list(ext_mod_scmversion_objs)
        if kernel_dir_scmversion_obj:
            scmversion_objs.append(kernel_dir_scmversion_obj)

        scmversion_map = {obj.path: obj for obj in scmversion_objs}

        return scmversion_map

    def call_setlocalversion_kernel_dir(self):
        if not self.setlocalversion or not self.kernel_dir:
            return None

        return PathPopen(
            self.kernel_rel,
            call_setlocalversion(self.setlocalversion, self.kernel_dir))

    def get_ext_modules(self):
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
            msg = ("WARNING: Unable to determine EXT_MODULES; scmversion "
                   "for external modules may be incorrect. "
                   "code={}, stderr={}\n").format(e.returncode,
                                                  e.stderr.strip())
            sys.stderr.write(msg)
        return []

    def call_setlocalversion_ext_modules(self, ext_modules):
        if not self.setlocalversion:
            return []

        ret = []
        for ext_mod in ext_modules:
            popen = call_setlocalversion(self.setlocalversion,
                                         os.path.realpath(ext_mod))
            ret.append(PathPopen(ext_mod, popen))
        return ret

    def async_get_source_date_epoch_kernel_dir(self):
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

    def print_result(
        self,
        scmversion_objs,
        source_date_epoch_objs,
    ):
        stable_source_date_epochs = " ".join(obj.collect()
                                             for obj in source_date_epoch_objs)
        print("STABLE_SOURCE_DATE_EPOCHS", stable_source_date_epochs)

        # If the list is empty, this prints "STABLE_SCMVERSIONS", and is
        # filtered by Bazel.
        print("STABLE_SCMVERSIONS",
              " ".join(path_popen.collect() for path_popen in scmversion_objs))


if __name__ == '__main__':
    sys.exit(Stamp().main())
