#!/usr/bin/env python3

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

import json
import os
import sys

BEGIN_MARK = "# update_common_kernels TEMPLATE_BEGIN"
END_MARK = "# update_common_kernels TEMPLATE_END"
ARCHS = ("aarch64", "x86_64")

def find_mark(lines, mark):
  for idx, line in enumerate(lines):
    if line.strip() == mark:
      return idx
  raise ValueError("Cannot find {}".format(mark))


def load_default_build_configs(this_dir):
  myglobals = {}
  with open(os.path.join(this_dir, "default_build_configs.bzl")) as f:
    exec(f.read(), myglobals)
  return myglobals["INTERESTING_BUILD_CONFIG_VARS"]


def update_common_kernels(this_dir, var_names):
  common_kernels = os.path.join(this_dir, "common_kernels.bzl")
  with open(common_kernels) as f:
    lines = f.read().splitlines()
  begin = find_mark(lines, BEGIN_MARK)
  end = find_mark(lines, END_MARK)

  replace = []
  for arch in ARCHS:
    build_config = "build.config.gki." + arch
    replace += emit_load_statements(build_config, "kernel_" + arch, var_names)
    build_config = "build.config.gki-debug." + arch
    replace += emit_load_statements(build_config, "kernel_" + arch + "_debug",
                                    var_names)

  replace.append("_ARCH_VALUES = {")
  for arch in ARCHS:
    replace += emit_alises("kernel_" + arch, var_names)
    replace += emit_alises("kernel_" + arch + "_debug", var_names)
  replace.append("}")

  lines = lines[:begin + 1] + replace + lines[end:]
  with open(common_kernels, "w") as f:
    f.write("\n".join(lines))
    f.write("\n")


def emit_load_statements(build_config, target_name, var_names):
  if not var_names:
    return []
  statements = ["load(", '    "@{}//:dict.bzl",'.format(build_config)]
  for var_name in sorted(var_names):
    statements.append('    {target_name}_{var_name} = "{var_name}",'.format(
        target_name=target_name.upper(), var_name=var_name.upper()))
  statements.append(")")
  return statements


def emit_alises(target_name, var_names):
  statements = ['    "{}": {{'.format(target_name)]
  for var_name in sorted(var_names):
    statements.append('        "{var_name}": {target_name}_{var_name},'.format(
        var_name=var_name.upper(),
        target_name=target_name.upper()
    ))
  statements.append("    },")
  return statements


def main():
  this_dir = os.path.dirname(sys.argv[0])
  var_names = load_default_build_configs(this_dir)
  update_common_kernels(this_dir, var_names)


if __name__ == "__main__":
  main()
