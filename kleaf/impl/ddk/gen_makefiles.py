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

import sys

from typing import Sequence, Set, TextIO, Dict


# Represents a directory in the filesystem
class Dir(object):
  def __init__(self, name: str = ""):
    # Name of this directory
    self.name: str = name
    # A list of files in the directory.
    self.__files: Set[str] = set()
    # A list of sub-directories.
    self.__dirs: Dict[str, "Dir"] = {}

  def add_file(self, src: Path):
    """Add a file, relative to this directory."""
    assert (not src.is_absolute())
    if len(src.parts) == 1:
      self.__files.add(src.parts[0])
      return

    first_part = src.parts[0]
    dir: Dir = self.__dirs.get(first_part)
    if dir is None:
      dir = Dir(name=first_part)
      self.__dirs[first_part] = dir
    dir.add_file(Path(*src.parts[1:]))

  def walk(self, f, root=Path()):
    """Walk the tree in an implementation-defined order.

    Args:
      f: The function to apply on each FsTree node. It should take two
        arguments:
        - The first argument is an FsTree object
        - The second argument is the path to the FsTree object.
      root: The root where `self` resides.
    """
    path = root / self.name
    f(self, path)
    for dir in self.__dirs.values():
      dir.walk(f, root=path)

  @property
  def files(self):
    return self.__files

  @property
  def subdirs(self):
    return self.__dirs.keys()

  def __str_list(self, indent=0):
    lst = [f"{' ' * indent}{self.name}/"]
    lst += [f"{' ' * indent}  {file}" for file in self.files]
    for dir in self.__dirs.values():
      lst += dir.__str_list(indent + 2)
    return lst

  def __str__(self):
    return "\n".join(self.__str_list())


def open_with_dir(path: str, *args):
  dir = os.path.dirname(path)
  if dir:
    os.makedirs(dir, exist_ok=True)
  return open(path, *args)


def build_tree(srcs: Sequence[Path], root: Path):
  root = Dir(str(root))
  for src in srcs:
    root.add_file(src)
  return root


def gen_kbuild(dir: Dir, path: Path):
  with open_with_dir(path / "Kbuild", "w") as out_file:
    for subdir in dir.subdirs:
      out_file.write(f"obj-m += {subdir}/\n")
    for src in dir.files:
      if not src.endswith(".c"):
        continue
      out = src[:-len(".c")] + ".o"
      out_file.write(f"obj-m += {out}\n")


def gen_ddk_makefile(
    output_makefiles: Path,
    # FIXME delete
    kernel_module_outs: TextIO,
    kernel_module_srcs: TextIO,
    ccflags: TextIO,
    package: str,
):
  with open_with_dir(output_makefiles / "Makefile", "w") as out_file:
    # FIXME W=1
    out_file.write(
        """modules modules_install clean:
\t$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) $(@)
""")

  package = os.path.normpath(package)
  srcs = kernel_module_srcs.readlines()
  srcs = [src.strip() for src in srcs]
  srcs = [Path(src[len(package) + 1:]) for src in srcs if
          os.path.commonpath((package, src)) == package]

  fs_tree = build_tree(srcs, output_makefiles)
  fs_tree.walk(gen_kbuild)

  with open_with_dir(output_makefiles / "Kbuild", "a") as out_file:
    out_file.write("\nsubdir-ccflags-y += ")
    out_file.write(ccflags.read())
    out_file.write("\n")


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--package")
  parser.add_argument("--kernel-module-outs", type=argparse.FileType())
  parser.add_argument("--kernel-module-srcs", type=argparse.FileType())
  parser.add_argument("--output-makefiles", type=Path)
  parser.add_argument("--ccflags", type=argparse.FileType())

  gen_ddk_makefile(**vars(parser.parse_args()))
