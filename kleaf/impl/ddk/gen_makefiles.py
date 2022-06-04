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
from pathlib import Path

from typing import Sequence, TextIO


def open_with_dir(path: Path, *args):
  dir = os.path.dirname(path)
  if dir:
    os.makedirs(dir, exist_ok=True)
  return open(path, *args)


def gen_ddk_makefile(
    output_makefiles: Path,
    kernel_module_out: str,
    kernel_module_srcs: TextIO,
    ccflags: TextIO,
    package: str,
):
  package = os.path.normpath(package)
  srcs = kernel_module_srcs.readlines()
  srcs = [src.strip() for src in srcs]
  srcs = [Path(src[len(package) + 1:]) for src in srcs if
          os.path.commonpath((package, src)) == package]

  assert kernel_module_out.endswith(".ko")
  kernel_module_name = kernel_module_out.removesuffix(".ko")

  with open(output_makefiles / "Kbuild", "a") as out_file:
    out_file.write(f"obj-m += {kernel_module_name}.o\n")
    for src in srcs:
      assert src.suffix == ".c", f"Invalid source {src}"
      if src.with_suffix("") == Path(kernel_module_name):
        continue
      out = src.with_suffix(".o")
      out_file.write(f"{kernel_module_name}-y += {out}\n")

    # FIXME this canbe in bazel because should only be one
    out_file.write("\nccflags-y += ")
    out_file.write(ccflags.read())
    out_file.write("\n")


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--package")
  parser.add_argument("--kernel-module-out")
  parser.add_argument("--kernel-module-srcs", type=argparse.FileType())
  parser.add_argument("--output-makefiles", type=Path)
  parser.add_argument("--ccflags", type=argparse.FileType())

  gen_ddk_makefile(**vars(parser.parse_args()))
