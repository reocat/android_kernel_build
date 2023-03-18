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

"""A target that configures a [`ddk_module`](#ddk_module)."""

load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelBuildOriginalEnvInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils")

def _ddk_config_impl(ctx):
    defconfig = ctx.file.defconfig

    if not defconfig:
        defconfig = ctx.attr.declare_file("{}/defconfig".format(ctx.attr.name))
        ctx.actions.write(defconfig, "")

    inputs = [
        ctx.file.kconfig,
        defconfig,
    ]
    inputs += ctx.attr.kernel_build[KernelBuildOriginalEnvInfo].env_info.dependencies
    transitive_inputs = [
        # TODO we probably only need scripts/kconfig/*.h
        # TODO maybe build conf from kernel_config rule instead.
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_hdrs,
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_scripts,
    ]
    out_dir = ctx.actions.declare_directory(ctx.attr.name + "/out_dir")
    command = ctx.attr.kernel_build[KernelBuildOriginalEnvInfo].env_info.setup
    command += """
        {set_src_arch_cmd}
        mkdir -p ${{KERNEL_DIR}}/arch/${{SRCARCH}}/configs/
        rsync -aL {defconfig} ${{KERNEL_DIR}}/arch/${{SRCARCH}}/configs/kleaf_ddk_defconfig
        make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} \\
          KBUILD_KCONFIG=$(realpath {kconfig}) \\
          kleaf_ddk_defconfig
        rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
        rsync -aL ${{OUT_DIR}}/include/ {out_dir}/include/
    """.format(
        set_src_arch_cmd = kernel_utils.set_src_arch_cmd(),
        kconfig = ctx.file.kconfig.path,
        defconfig = defconfig.path,
        out_dir = out_dir.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_dir],
        command = command,
        mnemonic = "DdkConfig",
        progress_message = "Creating DDK module configuration {}".format(ctx.label),
    )

    return DefaultInfo(files = depset([out_dir]))

ddk_config = rule(
    implementation = _ddk_config_impl,
    doc = "A target that configures a [`ddk_module`](#ddk_module).",
    attrs = {
        "kernel_build": attr.label(
            doc = "[`kernel_build`](#kernel_build).",
            providers = [
                KernelBuildOriginalEnvInfo,
                KernelBuildExtModuleInfo,
            ],
            mandatory = True,
        ),
        "kconfig": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The `Kconfig` file.",
        ),
        "defconfig": attr.label(
            allow_single_file = True,
            doc = "The `defconfig` file.",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
