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

load(":common_providers.bzl", "KernelEnvInfo")
load(":debug.bzl", "debug")

def _makefile_impl(ctx):
    module_srcs_txt = ctx.actions.declare_file("{}/module_srcs.txt".format(ctx.attr.name))
    ctx.actions.write(
        module_srcs_txt,
        content = "\n".join([src.short_path for src in ctx.files.module_srcs]),
    )
    module_outs_txt = ctx.actions.declare_file("{}/module_outs.txt".format(ctx.attr.name))
    ctx.actions.write(
        module_outs_txt,
        content = "\n".join(ctx.attr.module_outs),
    )

    # configs = ctx.attr.configs
    output_makefile = ctx.actions.declare_file("{}/Makefile".format(ctx.attr.name))

    inputs = [ctx.file._gen_makefile, module_srcs_txt, module_outs_txt]
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies

    command = ctx.attr.kernel_build[KernelEnvInfo].setup
    command += """
             # Generate Makefile for DDK module
               {gen_makefile} \\
                 --kernel-module-srcs {module_srcs_txt} \\
                 --kernel-module-outs {module_outs_txt} \\
                 --output-makefile {makefile} \\
                 --package {package} \\
                 --include-dirs {include_dirs} \\

    """.format(
        gen_makefile = ctx.file._gen_makefile.path,
        # configs = " ".join([_ddk_mod_config_info_to_string(config) for config in ctx.attr.configs]),
        makefile = output_makefile.path,
        module_srcs_txt = module_srcs_txt.path,
        module_outs_txt = module_outs_txt.path,
        package = ctx.label.package,
        include_dirs = " ".join(ctx.attr.include_dirs),
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [output_makefile],
        command = command,
        progress_message = "Generating Makefile {}".format(ctx.label),
    )
    return DefaultInfo(files = depset([output_makefile]))

makefile = rule(
    implementation = _makefile_impl,
    doc = "Generate `Makefile` for `ddk_module`",
    attrs = {
        #        "configs": attr.label_list(
        #            providers = [_DdkModConfigInfo],
        #        ),
        "include_dirs": attr.string_list(),
        "module_srcs": attr.label_list(allow_files = True),
        "module_outs": attr.string_list(),
        "kernel_build": attr.label(
            providers = [KernelEnvInfo],
        ),
        "_gen_makefile": attr.label(
            allow_single_file = True,
            default = "//build/kernel/kleaf/impl:ddk/gen_makefile.py",
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    },
)
