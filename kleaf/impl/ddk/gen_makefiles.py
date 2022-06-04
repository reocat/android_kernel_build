#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""
Generate a DDK module Makefile
"""
import argparse
import os
import shlex
import pathlib

from typing import TextIO


def gen_ddk_makefile(
    output_makefiles: pathlib.Path,
    kernel_module_out: pathlib.Path,
    kernel_module_srcs: TextIO,
    ccflags_txt: TextIO,
    include_dirs_txt: TextIO,
    package: str,
):
  package = os.path.normpath(package)
  ccflags = ccflags_txt.read()
  include_dirs = include_dirs_txt.read().split("\n")
  srcs = kernel_module_srcs.readlines()
  srcs = [src.strip() for src in srcs]
  srcs = [pathlib.Path(src[len(package) + 1:]) for src in srcs if
          os.path.commonpath((package, src)) == package]

  assert kernel_module_out.suffix == ".ko", f"Invalid output: {kernel_module_out}"

  kbuild = output_makefiles / kernel_module_out.parent / "Kbuild"
  os.makedirs(kbuild.parent, exist_ok=True)

  with open(kbuild, "w") as out_file:
    out_file.write(f"obj-m += {kernel_module_out.with_suffix('.o').name}\n")
    for src_str in srcs:
      src = pathlib.Path(src_str)
      # Ignore non-sources
      if src.suffix != ".c":
        continue
      # Ignore self (don't omit obj-foo += foo.o)
      if src.with_suffix(".ko") == kernel_module_out:
        continue
      assert src.parent == kernel_module_out.parent, \
        f"{src} is not a valid source because it is not under {kernel_module_out.parent}"
      out = src.with_suffix(".o").name
      out_file.write(f"{kernel_module_out.with_suffix('').name}-y += {out}\n")

    # FIXME this can be in bazel because should only be one
    out_file.write("\nccflags-y += ")
    out_file.write(ccflags)
    out_file.write("\n")

    #    //path/to/package:target/name/foo.ko
    # =>   path/to/package/target/name
    rel_root_reversed = pathlib.Path(package) / kernel_module_out.parent
    rel_root = "/".join([".."] * len(rel_root_reversed.parts))

    out_file.write("\nccflags-y += \\\n")
    for include_dir in include_dirs:
      out_file.write("  ")
      out_file.write(shlex.quote(f"-I$(srctree)/$(src)/{rel_root}/{include_dir}"))
      out_file.write("\\\n")
    out_file.write("\n")

  top_kbuild = output_makefiles / "Kbuild"
  if top_kbuild != kbuild:
    with open(top_kbuild, "w") as out_file:
      out_file.write(f"obj-y += {kernel_module_out.parent}/")


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--package")
  parser.add_argument("--kernel-module-out", type=pathlib.Path)
  parser.add_argument("--kernel-module-srcs", type=argparse.FileType())
  parser.add_argument("--output-makefiles", type=pathlib.Path)
  parser.add_argument("--ccflags_txt", type=argparse.FileType())
  parser.add_argument("--include_dirs_txt", type=argparse.FileType())

  gen_ddk_makefile(**vars(parser.parse_args()))
