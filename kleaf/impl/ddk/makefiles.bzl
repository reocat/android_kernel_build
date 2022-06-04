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

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":common_providers.bzl", "KernelEnvInfo")
load(":debug.bzl", "debug")

def _makefiles_impl(ctx):
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

    ccflags = []
    for d in ctx.attr.local_include_dirs:
        ccflags.append("-I$(srctree)/$(src)/{}".format(d))
    for d in ctx.attr.kernel_include_dirs:
        ccflags.append("-I$(srctree)/{}".format(d))
    ccflags_txt = ctx.actions.declare_file("{}/ccflags.txt".format(ctx.attr.name))
    ctx.actions.write(ccflags_txt, content = " \\\n  ".join([shell.quote(flag) for flag in ccflags]))

    output_makefiles = ctx.actions.declare_directory("{}/makefiles".format(ctx.attr.name))

    inputs = [
        ctx.file._gen_makefile,
        module_srcs_txt,
        module_outs_txt,
        ccflags_txt,
    ]

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
             # Generate Makefile for DDK module
               {gen_makefile} \\
                 --kernel-module-srcs {module_srcs_txt} \\
                 --kernel-module-outs {module_outs_txt} \\
                 --output-makefiles {output_makefiles} \\
                 --package {package} \\
                 --ccflags {ccflags_txt} \\

    """.format(
        gen_makefile = ctx.file._gen_makefile.path,
        output_makefiles = output_makefiles.path,
        module_srcs_txt = module_srcs_txt.path,
        module_outs_txt = module_outs_txt.path,
        package = ctx.label.package,
        ccflags_txt = ccflags_txt.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [output_makefiles],
        command = command,
        progress_message = "Generating Makefile {}".format(ctx.label),
    )
    return DefaultInfo(files = depset([output_makefiles]))

makefiles = rule(
    implementation = _makefiles_impl,
    doc = "Generate `Makefile` and `Kbuild` files for `ddk_module`",
    attrs = {
        "local_include_dirs": attr.string_list(),
        "kernel_include_dirs": attr.string_list(),
        "module_srcs": attr.label_list(allow_files = True),
        "module_outs": attr.string_list(),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_gen_makefile": attr.label(
            allow_single_file = True,
            default = "//build/kernel/kleaf/impl:ddk/gen_makefiles.py",
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    },
)
