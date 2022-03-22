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

import sys

def collect(popen_obj):
  stdout, _ = popen_obj.communicate()
  if popen_obj.returncode != 0:
    sys.stderr.write("ERROR: return code is {}\n".format(popen_obj.returncode))
    sys.exit(1)
  return stdout.strip()

def main():
  working_dir = "build/kernel/kleaf/workspace_status_dir"
  kernel_dir = os.path.realpath(".source_date_epoch_dir")

  setlocalversion = os.path.join(kernel_dir, "scripts/setlocalversion")
  if not os.access(setlocalversion, os.X_OK):
    setlocalversion = None

  stable_scmversion_obj = None
  if setlocalversion and os.path.isdir(kernel_dir):
    stable_scmversion_obj = subprocess.Popen([setlocalversion, kernel_dir], text=True, stdout = subprocess.PIPE, cwd=working_dir)

  ext_modules = []
  stable_scmversion_extmod_objs = []
  if setlocalversion:
    ext_modules = subprocess.check_output("""
  source build/build_utils.sh
  source build/_setup_env.sh
  echo $EXT_MODULES
  """, shell = True, text = True).split()
    stable_scmversion_extmod_objs = [subprocess.Popen([setlocalversion, os.path.realpath(ext_mod)], text=True, stdout = subprocess.PIPE, cwd=working_dir) for ext_mod in ext_modules]

  stable_source_date_epoch = None
  stable_source_date_epoch_obj = None
  if os.environ.get("SOURCE_DATE_EPOCH"):
    stable_source_date_epoch = os.environ["SOURCE_DATE_EPOCH"]
  elif os.path.isdir(kernel_dir):
    stable_source_date_epoch_obj = subprocess.Popen(["git", "-C", kernel_dir, "log", "-1", "--pretty=%ct"], text=True, stdout = subprocess.PIPE, cwd=working_dir)
  else:
    stable_source_date_epoch = 0

  print("STABLE_SCMVERSION", collect(stable_scmversion_obj))
  if stable_source_date_epoch_obj:
    stable_source_date_epoch = collect(stable_source_date_epoch_obj)
  print("STABLE_SOURCE_DATE_EPOCH", stable_source_date_epoch)

  print("STABLE_SCMVERSION_EXT_MOD", " ".join("{}:{}".format(ext_mod, result) for ext_mod, result in zip(ext_modules, [collect(obj) for obj in stable_scmversion_extmod_objs])))

if __name__ == '__main__':
    main()
