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
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

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

    tools = [ctx.attr.kernel_build[KernelBuildExtModuleInfo].config_env_and_outputs_info.tools]

    # For merge_config
    transitive_inputs = [
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].config_env_and_outputs_info.inputs,
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_scripts,
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_kconfig,
    ]

    config = ctx.actions.declare_file(ctx.attr.name + "/.config")
    # combined_defconfig = ctx.actions.declare_file(ctx.attr.name + "/combined_defconfig")

    # auto_conf = ctx.actions.declare_file(ctx.attr.name + "/include/config/auto.conf")
    # auto_conf_h = ctx.actions.declare_file(ctx.attr.name + "/include/generated/autoconf.h")
    # rustc_cfg = ctx.actions.declare_file(ctx.attr.name + "/include/generated/rustc_cfg")
    outputs = [
        config,
        # combined_defconfig,
        # auto_conf,
        # auto_conf_h,
        # rustc_cfg,
    ]

    intermediates_dir = utils.intermediates_dir(ctx)

    # Need kernel_env info to get $KERNEL_DIR
    command = ctx.attr.kernel_build[KernelBuildExtModuleInfo].config_env_and_outputs_info.get_setup_script(
        data = ctx.attr.kernel_build[KernelBuildExtModuleInfo].config_env_and_outputs_info.data,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += kernel_utils.set_src_arch_cmd()
    command += """
      # FIXME
        set -x

        mkdir -p {intermediates_dir}

      # Create module-specific .config file
      # FIXME use make?
        KCONFIG_CONFIG={intermediates_dir}/.config.module_frag \\
            {conf} -s --defconfig={defconfig} {kconfig}

      # Merge into .config from kernel_build
        KCONFIG_CONFIG=${{OUT_DIR}}/.config.tmp \\
            ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh \\
                -m -r \\
                ${{OUT_DIR}}/.config \\
                {intermediates_dir}/.config.module_frag
        mv ${{OUT_DIR}}/.config.tmp ${{OUT_DIR}}/.config

      # Regenerate auto.conf, autoconf.h etc.
        cp {kconfig} {intermediates_dir}/Kconfig.ext
        export KCONFIG_EXT_PREFIX=$(realpath {intermediates_dir} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
        make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} oldconfig

      # Copy outputs
        rsync -aL ${{OUT_DIR}}/.config {config}
    """.format(
        intermediates_dir = intermediates_dir,
        kconfig = ctx.file.kconfig.path,
        defconfig = defconfig.path,
        config = config.path,
        # export KCONFIG_AUTOCONFIG={auto_conf}
        # export KCONFIG_AUTOHEADER={auto_conf_h}
        # export KCONFIG_RUSTCCFG={rustc_cfg}
        # auto_conf = auto_conf.path,
        # auto_conf_h = auto_conf_h.path,
        # rustc_cfg = rustc_cfg.path,
        conf = conf.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = depset(inputs, transitive = transitive_inputs),
        tools = tools,
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
        # "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
