#!/usr/bin/env python3

"""
Convert Makefile to BUILD.bazel for kernel modules
"""

import argparse
import os
import subprocess
import sys


def go_to_workspace_root():
  while True:
    cwd = os.getcwd()
    if "WORKSPACE" in os.listdir(cwd):
      break
    new_cwd = os.path.dirname(cwd)
    if new_cwd == cwd:
      raise RuntimeError("Can't find WORKSPACE")
    os.chdir(new_cwd)
  return cwd


def handle_makefile(dir: str):
  """
  Use heuristics to determine kernel modules created by makefile.
  """
  srcs = []
  objects = []
  makefile_path = os.path.join(dir, "Makefile")
  kbuild_path = os.path.join(dir, "Kbuild")
  for path in (makefile_path, kbuild_path):
    if not os.path.isfile(path):
      continue
    srcs.append(os.path.basename(path))
    with open(path) as makefile:
      print(f"Parsing {path}...")
      for line in makefile.readlines():
        line = line.strip()
        if line.startswith("obj-"):
          equal = line.find('=')
          if equal < 0:
            sys.stderr.write(
                f"Warning: unknown line in {path}: \"{line}\"\n")
            continue
          for obj in line[equal + 1:].strip().split(" "):
            if obj.endswith(".o"):
              objects.append(obj)
              continue
            possible_subdir = os.path.join(dir, obj)
            if os.path.isdir(possible_subdir):
              subdir_srcs, subdir_objects = handle_makefile(possible_subdir)
              srcs += [os.path.join(obj, subdir_src) for subdir_src in
                       subdir_srcs]
              objects += [os.path.join(obj, subdir_obj) for subdir_obj in
                          subdir_objects]
              continue
            sys.stderr.write(
                f"Warning: Unknown output file in {path}: {obj}\n")
  return srcs, objects


def handle_module(ext_module: str, suffix: str, kernel_build_prefix: str,
    force: bool):
  if ext_module.endswith("/"):
    ext_module = ext_module[:-1]
  build_path = os.path.join(ext_module, "BUILD.bazel")
  if not force and os.path.isfile(build_path):
    print(f"Skipping {ext_module} because BUILD.bazel already exists")
    return

  srcs, objects = handle_makefile(ext_module)
  srcs = set(srcs)
  objects = set(objects)
  if "Makefile" in srcs:
    srcs.remove("Makefile")

  if len(objects) == 0:
    sys.stderr.write(
        f"Warning: Can't find any modules in {ext_module}\n")
  else:
    print(ext_module + "\n" + (
        "\n".join(f"   {out[:-2]}.ko" for out in objects)))

  outs = "".join(f'        "{obj[:-2]}.ko",\n' for obj in sorted(objects))
  srcs_str = "".join(f'        "{src}",\n' for src in srcs)

  content = f"""# NOTE: THIS FILE IS EXPERIMENTAL FOR THE BAZEL MIGRATION AND NOT USED FOR
# YOUR BUILDS CURRENTLY.
#
# It is not yet the source of truth for your build. If you're looking to modify
# the build file, modify the Android.bp file instead. Do *not* modify this file
# unless you have coordinated with the team managing the Soong to Bazel
# migration.

load("//build/kleaf:kernel.bzl", "kernel_module")

[kernel_module(
    name = name,
    srcs = glob([
        "**/*.c",
        "**/*.h",
{srcs_str}    ]),
    outs = [
{outs}    ],
    kernel_build = kernel_build,
    makefile = ":Makefile",
) for name, kernel_build in [
    (
        "{os.path.basename(ext_module)}.{suffix}",
        "{kernel_build_prefix}:{suffix}",
    ),
]]
"""
  with open(build_path, "w") as build:
    build.write(content)
  print(f"Written {build_path}")


def get_ext_modules_for_build_config(build_config: str):
  ext_modules = subprocess.check_output(
      f"BUILD_CONFIG={build_config} source build/_setup_env.sh && echo $EXT_MODULES",
      shell=True, encoding='UTF-8')
  ext_modules = ext_modules.strip()
  ext_modules = ext_modules.split(" ")
  return ext_modules


def main(ext_mods: list, f: bool, kernel_build_prefix: str,
    build_config: str):
  go_to_workspace_root()
  if not ext_mods:
    ext_mods = get_ext_modules_for_build_config(build_config)

  base = os.path.basename(build_config)
  assert base.startswith(
      "build.config."), f"Invalid build config {build_config}"
  suffix = base[len("build.config."):]

  for ext_module in ext_mods:
    handle_module(ext_module, suffix, kernel_build_prefix, force=f)


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("ext_mods", nargs="*",
                      help="directories containing external module. If missing, infer from --build-config")
  parser.add_argument("--kernel-build-prefix", required=True,
                      help="Prefix to kernel build labels (e.g. //common)")
  parser.add_argument("--build-config", required=True,
                      help="build.config file relative to workspace root (e.g. common/build.config.aarch64)")
  parser.add_argument("-f", action="store_true", default=False,
                      help="overwrite existing BUILD.bazel files")
  args = parser.parse_args()
  main(**vars(args))
