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

"""Build dtbo."""

load(":common_providers.bzl", "KernelBuildInfo", "KernelEnvAndOutputsInfo")
load(":debug.bzl", "debug")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _dtbo_impl(ctx):
    output = ctx.actions.declare_file("{}/dtbo.img".format(ctx.label.name))
    dtbo_staging_dir = output.dirname + "/staging"
    inputs = []
    transitive_inputs = [target.files for target in ctx.attr.srcs]
    transitive_inputs.append(ctx.attr.kernel_build[KernelEnvAndOutputsInfo].inputs)
    tools = ctx.attr.kernel_build[KernelEnvAndOutputsInfo].tools
    command = ctx.attr.kernel_build[KernelEnvAndOutputsInfo].get_setup_script(
        data = ctx.attr.kernel_build[KernelEnvAndOutputsInfo].data,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )

    if ctx.file.config_file:
        inputs += [ctx.file.config_file]
        command += """
             mkdir -p {dtbo_staging_dir}
             cp -vf {srcs} {dtbo_staging_dir}

             # make dtbo
               mkdtimg cfg_create {output} ${{MKDTIMG_FLAGS}} {config} -d {dtbo_staging_dir}
        """.format(
            output = output.path,
            srcs = " ".join([f.path for f in ctx.files.srcs]),
            config = ctx.file.config_file.path,
            dtbo_staging_dir = dtbo_staging_dir,
        )
    else:
        command += """
                 # make dtbo
                   mkdtimg create {output} ${{MKDTIMG_FLAGS}} {srcs}
        """.format(
            output = output.path,
            srcs = " ".join([f.path for f in ctx.files.srcs]),
        )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "Dtbo",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [output],
        tools = tools,
        progress_message = "Building dtbo {}".format(ctx.label),
        command = command,
    )
    return DefaultInfo(files = depset([output]))

dtbo = rule(
    implementation = _dtbo_impl,
    doc = "Build dtbo.",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvAndOutputsInfo, KernelBuildInfo],
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "config_file": attr.label(
            allow_single_file = True,
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    },
)
