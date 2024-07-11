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

"""Support `compile_commands.json`."""

load(
    ":abi/abi_transitions.bzl",
    "FORCE_IGNORE_BASE_KERNEL_SETTING",
)
load(
    ":common_providers.bzl",
    "CompileCommandsInfo",
)
load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _kernel_compile_commands_transition_impl(_settings, _attr):
    return {
        FORCE_IGNORE_BASE_KERNEL_SETTING: True,
        "//build/kernel/kleaf/impl:build_compile_commands": True,
    }

_kernel_compile_commands_transition = transition(
    implementation = _kernel_compile_commands_transition_impl,
    inputs = [],
    outputs = [
        FORCE_IGNORE_BASE_KERNEL_SETTING,
        "//build/kernel/kleaf/impl:build_compile_commands",
    ],
)

def _kernel_compile_commands_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    if ctx.attr.kernel_build:
        # buildifier: disable=print
        print("""WARNING: {}: kernel_compile_commands.kernel_build is deprecated. Use deps instead.""".format(
            ctx.label,
        ))

    script = ctx.actions.declare_file(ctx.attr.name + ".sh")
    script_content = hermetic_tools.run_setup + """
        OUTPUT=${1:-${BUILD_WORKSPACE_DIRECTORY}/compile_commands.json}
        echo '[' > ${OUTPUT}
    """

    direct_runfiles = []
    for dep in [ctx.attr.kernel_build]:
        for info in dep[CompileCommandsInfo].infos.to_list():

            # 1d;$d deletes the first line `[` and last line `]`.
            #   A more robust way would be to parse the JSON list to concatenate them.
            #   But this is good enough.
            script_content += """
                sed -e "1d;$d" \\
                    -e "s:\\${{COMMON_OUT_DIR}}:${{BUILD_WORKSPACE_DIRECTORY}}/{compile_commands_common_out_dir}:g" \\
                    -e "s:\\${{ROOT_DIR}}:${{BUILD_WORKSPACE_DIRECTORY}}:g" \\
                    {compile_commands_with_vars} >> ${{OUTPUT}}
            """.format(
                compile_commands_with_vars = info.compile_commands_with_vars.short_path,
                compile_commands_common_out_dir = info.compile_commands_common_out_dir.path,
            )
            direct_runfiles.append(info.compile_commands_with_vars)

    script_content += """
        echo ']' >> ${OUTPUT}
        echo "Written to ${OUTPUT}"
    """
    ctx.actions.write(script, script_content, is_executable = True)

    return DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(
            files = direct_runfiles,
            transitive_files = hermetic_tools.deps,
        ),
    )

kernel_compile_commands = rule(
    implementation = _kernel_compile_commands_impl,
    doc = """Define an executable that creates `compile_commands.json` from a `kernel_build`.""",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            doc = "The `kernel_build` rule to extract from.",
            providers = [CompileCommandsInfo],
        ),
        # Allow any package to use kernel_compile_commands because it is a public API.
        # The ACK source tree may be checked out anywhere; it is not necessarily //common
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
    cfg = _kernel_compile_commands_transition,
    toolchains = [hermetic_toolchain.type],
)
