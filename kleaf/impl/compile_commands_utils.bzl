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

"""Utility functions for building compile_commands.json."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":abi/base_kernel_utils.bzl", "base_kernel_utils")
load(":common_providers.bzl", "KernelBuildInfo")

def _compile_commands_config_settings_raw():
    """Attributes of rules that supports `compile_commands.json`."""
    return {
        "_build_compile_commands": "//build/kernel/kleaf/impl:build_compile_commands",
    }

def _kernel_build_step(ctx):
    """Returns a step for grabbing required files for `compile_commands.json`

    Args:
        ctx: `kernel_build` ctx

    Returns:
        A struct with these fields:
        * inputs
        * tools
        * outputs
        * cmd
        * restore_out_dir_cmd
        * compile_commands_out_dir
        * compile_commands_with_vars
    """
    cmd = ""
    prolog = ""
    compile_commands_with_vars = None
    out_dir = None
    outputs = []
    inputs = []
    if ctx.attr._build_compile_commands[BuildSettingInfo].value:
        out_dir = ctx.actions.declare_directory("{name}/compile_commands_out_dir".format(name = ctx.label.name))
        compile_commands_with_vars = ctx.actions.declare_file(
            "{name}/compile_commands_with_vars.json".format(name = ctx.label.name),
        )
        outputs += [out_dir, compile_commands_with_vars]

        additional_includes = ""
        base_kernel = base_kernel_utils.get_base_kernel(ctx)
        if base_kernel:
            base_kernel_out_dir = base_kernel[KernelBuildInfo].compile_commands_out_dir
            inputs.append(base_kernel_out_dir)
            prolog = """
                rsync -aL --chmod=D+w,F+w {base_kernel_out_dir}/ ${{OUT_DIR}}/
            """.format(
                base_kernel_out_dir = base_kernel_out_dir.path,
                out_dir = out_dir.path,
            )
        else:
            additional_includes = " ".join([
                "--include",
                "'*.a'",
            ])

        cmd = """
            rsync -a --prune-empty-dirs \\
                --include '*/' \\
                --include '*.c' \\
                --include '*.h' \\
                {additional_includes} \\
                --exclude '*' ${{OUT_DIR}}/ {out_dir}/
            sed -e "s:${{OUT_DIR}}:\\${{OUT_DIR}}:g;s:${{ROOT_DIR}}:\\${{ROOT_DIR}}:g" \\
                ${{OUT_DIR}}/compile_commands.json > {compile_commands_with_vars}
        """.format(
            out_dir = out_dir.path,
            additional_includes = additional_includes,
            compile_commands_with_vars = compile_commands_with_vars.path,
        )
    return struct(
        inputs = inputs,
        tools = [],
        cmd = cmd,
        prolog = prolog,
        outputs = outputs,
        compile_commands_with_vars = compile_commands_with_vars,
        compile_commands_out_dir = out_dir,
    )

def _additional_make_goals(ctx):
    """Returns a list of additional `MAKE_GOALS`.

    Args:
        ctx: ctx
    """
    if ctx.attr._build_compile_commands[BuildSettingInfo].value:
        return ["compile_commands.json"]
    return []

compile_commands_utils = struct(
    kernel_build_step = _kernel_build_step,
    config_settings_raw = _compile_commands_config_settings_raw,
    additional_make_goals = _additional_make_goals,
)
