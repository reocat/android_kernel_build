# Copyright (C) 2023 The Android Open Source Project
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
    "DdkConfigInfo",
    "KernelBuildExtModuleInfo",
    "KernelEnvAndOutputsInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

def _ddk_config_impl(ctx):
    module_label = Label(str(ctx.label).removesuffix("_config"))
    split_deps = kernel_utils.split_kernel_module_deps(ctx.attr.module_deps, module_label)
    ddk_config_deps = split_deps.ddk_configs

    out_dir = ctx.actions.declare_directory(ctx.attr.name + "/out_dir")

    _create_main_action(
        ctx = ctx,
        out_dir = out_dir,
        ddk_config_deps = ddk_config_deps,
    )

    env_and_outputs_info = _create_env_and_outputs_info(
        ctx = ctx,
        out_dir = out_dir,
    )

    ddk_config_info = _create_ddk_config_info(
        ctx = ctx,
        ddk_config_deps = ddk_config_deps,
    )

    return [
        DefaultInfo(files = depset([out_dir])),
        env_and_outputs_info,
        ddk_config_info,
    ]

def _create_merge_dot_config_step(ctx, ddk_config_deps):
    cmd = ""
    inputs = []
    need_oldconfig = bool(ctx.file.defconfig)

    if ctx.file.defconfig:
        inputs.append(ctx.file.defconfig)
        cmd = """
            # Merge module-specific defconfig into .config from kernel_build
            KCONFIG_CONFIG=${{OUT_DIR}}/.config.tmp \\
                ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh \\
                    -m -r \\
                    ${{OUT_DIR}}/.config \\
                    {defconfig} > /dev/null
            mv ${{OUT_DIR}}/.config.tmp ${{OUT_DIR}}/.config
        """.format(
            defconfig = ctx.file.defconfig.path,
        )

    return struct(
        inputs = inputs,
        cmd = cmd,
        need_oldconfig = need_oldconfig,
    )

def _create_kconfig_ext_step(ctx, _ddk_config_deps):
    inputs = []
    intermediates_dir = utils.intermediates_dir(ctx)
    need_oldconfig = ctx.file.kconfig
    cmd = ""

    if need_oldconfig:
        cmd += """
            mkdir -p {intermediates_dir}
            if [[ -f ${{KERNEL_DIR}}/${{KCONFIG_EXT_PREFIX}}/Kconfig.ext ]]; then
                echo 'source "'"${{KCONFIG_EXT_PREFIX}}/Kconfig.ext"'"' > {intermediates_dir}/Kconfig.ext
            fi
            KCONFIG_EXT_PREFIX=$(realpath {intermediates_dir} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
        """.format(
            intermediates_dir = intermediates_dir,
        )

    if ctx.file.kconfig:
        inputs.append(ctx.file.kconfig)
        cmd += """
            (
                mod_kconfig_rel=$(realpath {kconfig} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})
                echo 'source "'"${{mod_kconfig_rel}}"'"' >> {intermediates_dir}/Kconfig.ext
            )
        """.format(
            intermediates_dir = intermediates_dir,
            kconfig = ctx.file.kconfig.path,
        )

    return struct(
        inputs = inputs,
        cmd = cmd,
        need_oldconfig = need_oldconfig,
    )

def _create_oldconfig_step(need_oldconfig):
    cmd = ""
    if need_oldconfig:
        cmd = """
            # Regenerate include/.
            # We could also run `make syncconfig` but syncconfig is an implementation detail
            # of Kbuild. Hence, just wipe out include/ to force it to be re-regenerated.
            rm -rf ${OUT_DIR}/include

            # Use olddefconfig because we want to use the (new and combined) .config as base, and
            # set unspecified values to their default value.
            make -C ${KERNEL_DIR} ${TOOL_ARGS} O=${OUT_DIR} \\
                KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX} \\
                olddefconfig
        """
    return struct(
        inputs = [],
        cmd = cmd,
    )

def _create_main_action(ctx, out_dir, ddk_config_deps):
    """Registers the main action that creates the output files."""
    config_env_and_outputs_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].config_env_and_outputs_info

    inputs = []

    transitive_inputs = [
        config_env_and_outputs_info.inputs,
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_scripts,
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_kconfig,
    ]

    tools = config_env_and_outputs_info.tools

    command = config_env_and_outputs_info.get_setup_script(
        data = config_env_and_outputs_info.data,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += kernel_utils.set_src_arch_cmd()

    merge_dot_config_step = _create_merge_dot_config_step(ctx, ddk_config_deps)
    kconfig_ext_step = _create_kconfig_ext_step(ctx, ddk_config_deps)

    need_oldconfig = merge_dot_config_step.need_oldconfig or kconfig_ext_step.need_oldconfig
    oldconfig_step = _create_oldconfig_step(need_oldconfig)

    steps = [
        merge_dot_config_step,
        kconfig_ext_step,
        oldconfig_step,
    ]
    for step in steps:
        inputs += step.inputs

    command += """
        {merge_config_cmd}
        {kconfig_ext_cmd}
        {oldconfig_cmd}

        # Copy outputs
        rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
        rsync -aL ${{OUT_DIR}}/include/ {out_dir}/include/
    """.format(
        merge_config_cmd = merge_dot_config_step.cmd,
        kconfig_ext_cmd = kconfig_ext_step.cmd,
        oldconfig_cmd = oldconfig_step.cmd,
        out_dir = out_dir.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = depset(inputs, transitive = transitive_inputs),
        tools = tools,
        outputs = [out_dir],
        command = command,
        mnemonic = "DdkConfig",
        progress_message = "Creating DDK module configuration {}".format(ctx.label),
    )

def _create_env_and_outputs_info(ctx, out_dir):
    """Creates info for module build."""

    # Info from kernel_build
    pre_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_env_and_outputs_info

    # Overlay module-specific configs
    restore_outputs_cmd = """
        rsync -aL {out_dir}/.config ${{OUT_DIR}}/.config
        rsync -aL --chmod=D+w {out_dir}/include/ ${{OUT_DIR}}/include/
    """.format(
        out_dir = out_dir.path,
    )
    return KernelEnvAndOutputsInfo(
        get_setup_script = _env_and_outputs_info_get_setup_script,
        inputs = depset([out_dir], transitive = [pre_info.inputs]),
        tools = pre_info.tools,
        data = struct(
            pre_info = pre_info,
            restore_ddk_config_outputs_cmd = restore_outputs_cmd,
        ),
    )

def _env_and_outputs_info_get_setup_script(data, restore_out_dir_cmd):
    """Returns the script for setting up module build."""
    pre_info = data.pre_info
    restore_ddk_config_outputs_cmd = data.restore_ddk_config_outputs_cmd

    script = pre_info.get_setup_script(
        data = pre_info.data,
        restore_out_dir_cmd = restore_out_dir_cmd,
    )
    script += restore_ddk_config_outputs_cmd

    return script

def _create_ddk_config_info(ctx, ddk_config_deps):
    return DdkConfigInfo(
        kconfig = depset(
            ctx.files.kconfig,
            transitive = [dep[DdkConfigInfo].kconfig for dep in ddk_config_deps],
            order = "postorder",
        ),
        defconfig = depset(
            ctx.files.defconfig,
            transitive = [dep[DdkConfigInfo].defconfig for dep in ddk_config_deps],
            order = "postorder",
        ),
    )

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
            doc = """The `Kconfig` file for this external module.

See
[`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
for its format.
""",
        ),
        "defconfig": attr.label(
            allow_single_file = True,
            doc = "The `defconfig` file.",
        ),
        "module_deps": attr.label_list(),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
