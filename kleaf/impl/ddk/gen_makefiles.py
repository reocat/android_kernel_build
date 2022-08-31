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
import textwrap
import pathlib


def _gen_makefile(
    package: pathlib.Path,
    module_symvers_list: list[pathlib.Path],
    output_makefiles: pathlib.Path,
):
    # kernel_module always executes in a sandbox. So ../ only traverses within
    # the sandbox.
    rel_root = "/".join([".."] * len(package.parts))

    content = ""

    for module_symvers in module_symvers_list:
        content += textwrap.dedent(f"""\
            EXTRA_SYMBOLS += $(OUT_DIR)/$(M)/{rel_root}/{module_symvers}
            """)

    content += textwrap.dedent("""\
        modules modules_install clean:
        \t$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) KBUILD_EXTRA_SYMBOLS="$(EXTRA_SYMBOLS)" $(@)
        """)

    os.makedirs(output_makefiles, exist_ok=True)
    with open(output_makefiles / "Makefile", "w") as out_file:
        out_file.write(content)


def gen_ddk_makefile(
    output_makefiles: pathlib.Path,
    kernel_module_out: pathlib.Path,
    kernel_module_srcs: list[pathlib.Path],
    include_dirs: list[pathlib.Path],
    module_symvers_list: list[pathlib.Path],
    package: pathlib.Path,
):
    _gen_makefile(
        package=package,
        module_symvers_list=module_symvers_list,
        output_makefiles=output_makefiles,
    )

    rel_srcs = []
    for src in kernel_module_srcs:
        if src.is_relative_to(package):
            rel_srcs.append(src.relative_to(package))

    assert kernel_module_out.suffix == ".ko", \
        f"Invalid output: {kernel_module_out}; must end with .ko"

    kbuild = output_makefiles / kernel_module_out.parent / "Kbuild"
    os.makedirs(kbuild.parent, exist_ok=True)

    with open(kbuild, "w") as out_file:
        out_file.write(f"obj-m += {kernel_module_out.with_suffix('.o').name}\n")
        for src in rel_srcs:
            # Ignore non-sources
            if src.suffix != ".c":
                continue
            # Ignore self (don't omit obj-foo += foo.o)
            if src.with_suffix(".ko") == kernel_module_out:
                continue
            assert src.parent == kernel_module_out.parent, \
                f"{src} is not a valid source because it is not under " \
                f"{kernel_module_out.parent}"
            out = src.with_suffix(".o").name
            out_file.write(
                f"{kernel_module_out.with_suffix('').name}-y += {out}\n")

        #    //path/to/package:target/name/foo.ko
        # =>   path/to/package/target/name
        rel_root_reversed = pathlib.Path(package) / kernel_module_out.parent
        rel_root = "/".join([".."] * len(rel_root_reversed.parts))

        out_file.write("\nccflags-y += \\\n")
        for include_dir in include_dirs:
            out_file.write("  ")
            out_file.write(
                shlex.quote(f"-I$(srctree)/$(src)/{rel_root}/{include_dir}"))
            out_file.write("\\\n")
        out_file.write("\n")

    top_kbuild = output_makefiles / "Kbuild"
    if top_kbuild != kbuild:
        os.makedirs(output_makefiles, exist_ok=True)
        with open(top_kbuild, "w") as out_file:
            out_file.write(f"obj-y += {kernel_module_out.parent}/")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--params", type=argparse.FileType())
    parser.add_argument("--package", type=pathlib.Path)
    parser.add_argument("--kernel-module-out", type=pathlib.Path)
    parser.add_argument("--kernel-module-srcs", type=pathlib.Path, nargs="*")
    parser.add_argument("--output-makefiles", type=pathlib.Path)
    parser.add_argument("--include_dirs", type=pathlib.Path, nargs="*")
    parser.add_argument("--module_symvers_list", type=pathlib.Path, nargs="*")

    args = parser.parse_args()
    if args.params:
        args = parser.parse_args(args.params.read().splitlines())

    delattr(args, "params")

    gen_ddk_makefile(**vars(args))
