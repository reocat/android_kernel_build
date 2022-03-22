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

import os
import subprocess
import shutil
import sys


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
                            text=True, stdout=subprocess.PIPE,
                            cwd=working_dir)
  return None


def get_make_vars(var_names):
  cmd = """
      source build/build_utils.sh
      source build/_setup_env.sh
  """
  cmd += "\n".join(["echo $" + var_name for var_name in var_names])
  try:
    lines = subprocess.check_output(cmd, shell=True, text=True).splitlines()
    return {k: v for k, v in zip(var_names, lines)}
  except subprocess.CalledProcessError as e:
    msg = "WARNING: Unable to determine variables {}; scmversion may be incorrect. code={}, stderr=\n{}\n".format(
        var_names, e.returncode, e.stderr)
    sys.stderr.write(msg)
    return {}


def collect(popen_obj):
  """Collect the result of a Popen object.

  Terminates the program if return code is non-zero.

  Return:
    stdout of the subprocess.
  """
  stdout, _ = popen_obj.communicate()
  if popen_obj.returncode != 0:
    sys.stderr.write("ERROR: return code is {}\n".format(popen_obj.returncode))
    sys.exit(1)
  return stdout.strip()


def main():
  kernel_dir = os.path.realpath(".source_date_epoch_dir")

  setlocalversion = os.path.join(kernel_dir, "scripts/setlocalversion")
  if not os.access(setlocalversion, os.X_OK):
    setlocalversion = None

  make_vars = get_make_vars(["EXT_MODULES"])

  stable_scmversion_obj = None
  if setlocalversion and os.path.isdir(kernel_dir):
    stable_scmversion_obj = call_setlocalversion(setlocalversion, kernel_dir)

  ext_modules = []
  stable_scmversion_extmod_objs = []
  if setlocalversion:
    ext_modules = make_vars.get("EXT_MODULES")
    if ext_modules:
      ext_modules = ext_modules.split()
    stable_scmversion_extmod_objs = [
        call_setlocalversion(setlocalversion, os.path.realpath(ext_mod))
        for ext_mod in ext_modules]

  stable_source_date_epoch = os.environ.get("SOURCE_DATE_EPOCH")
  stable_source_date_epoch_obj = None
  if not stable_source_date_epoch and os.path.isdir(kernel_dir) and shutil.which("git"):
    stable_source_date_epoch_obj = subprocess.Popen(
        ["git", "-C", kernel_dir, "log", "-1", "--pretty=%ct"], text=True,
        stdout=subprocess.PIPE)
  else:
    stable_source_date_epoch = 0

  # Wait for subprocesses to finish, and print result.

  print("STABLE_SCMVERSION", collect(stable_scmversion_obj))

  if stable_source_date_epoch_obj:
    stable_source_date_epoch = collect(stable_source_date_epoch_obj)
  print("STABLE_SOURCE_DATE_EPOCH", stable_source_date_epoch)

  print("STABLE_SCMVERSION_EXT_MOD", " ".join(
      "{}:{}".format(ext_mod, result) for ext_mod, result in zip(ext_modules,
                                                                 [collect(obj)
                                                                  for obj in
                                                                  stable_scmversion_extmod_objs])))

  return 0


if __name__ == '__main__':
  sys.exit(main())
