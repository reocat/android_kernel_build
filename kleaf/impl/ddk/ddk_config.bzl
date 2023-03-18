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

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
)
load(":debug.bzl", "debug")

def _ddk_config_impl(ctx):
    defconfig = ctx.file.defconfig

    if not defconfig:
        defconfig = ctx.attr.declare_file("{}/defconfig".format(ctx.attr.name))
        ctx.actions.write(defconfig, "")

    conf = ctx.attr.kernel_build[KernelBuildExtModuleInfo].conf

    inputs = [
        ctx.file.kconfig,
        defconfig,
        # Technically this is a tool built for host, but right now it comes from
        # kernel_config. kernel_config is built in the target platform. If we
        # were to put it in tools, a separate kernel_config built with the exec
        # platform would be built.
        conf,
    ]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    config = ctx.actions.declare_file(ctx.attr.name + "/.config")
    auto_conf = ctx.actions.declare_file(ctx.attr.name + "/include/config/auto.conf")
    auto_conf_h = ctx.actions.declare_file(ctx.attr.name + "/include/generated/autoconf.h")
    rustc_cfg = ctx.actions.declare_file(ctx.attr.name + "/include/generated/rustc_cfg")
    outputs = [
        config,
        auto_conf,
        auto_conf_h,
        rustc_cfg,
    ]
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        export KCONFIG_CONFIG={config}
        export KCONFIG_AUTOCONFIG={auto_conf}
        export KCONFIG_AUTOHEADER={auto_conf_h}
        export KCONFIG_RUSTCCFG={rustc_cfg}
        {conf} -s --defconfig={defconfig} {kconfig}
    """.format(
        kconfig = ctx.file.kconfig.path,
        defconfig = defconfig.path,
        config = config.path,
        auto_conf = auto_conf.path,
        auto_conf_h = auto_conf_h.path,
        rustc_cfg = rustc_cfg.path,
        conf = conf.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command,
        mnemonic = "DdkConfig",
        progress_message = "Creating DDK module configuration {}".format(ctx.label),
    )

    return DefaultInfo(files = depset(outputs))

ddk_config = rule(
    implementation = _ddk_config_impl,
    doc = "A target that configures a [`ddk_module`](#ddk_module).",
    attrs = {
        "kernel_build": attr.label(
            doc = "[`kernel_build`](#kernel_build).",
            providers = [
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
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
