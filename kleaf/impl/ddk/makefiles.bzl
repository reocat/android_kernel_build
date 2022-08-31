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

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":common_providers.bzl", "KernelEnvInfo", "ModuleSymversInfo")
load(":debug.bzl", "debug")
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo")
load(":utils.bzl", "utils")

def _makefiles_impl(ctx):
    output_makefiles = ctx.actions.declare_directory("{}/makefiles".format(ctx.attr.name))

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("--params=%s")

    args.add("--kernel-module-srcs")
    args.add_all(ctx.files.module_srcs)

    args.add_all([
        "--kernel-module-out",
        ctx.attr.module_out,
        "--output-makefiles",
        output_makefiles.path,
        "--package",
        ctx.label.package,
    ])

    args.add("--include_dirs")

    # TODO use depset
    exported_include_dirs = []
    for hdr in ctx.attr.module_hdrs + ctx.attr.module_exported_hdrs + ctx.attr.module_deps:
        exported_include_dirs += hdr[DdkHeadersInfo].exported_include_dirs
    args.add_all(exported_include_dirs, uniquify = True)

    args.add("--module_symvers_list")
    for dep in ctx.attr.module_deps:
        args.add(dep[ModuleSymversInfo].restore_path)

    ctx.actions.run(
        outputs = [output_makefiles],
        executable = ctx.executable._gen_makefile,
        arguments = [args],
        progress_message = "Generating Makefile {}".format(ctx.label),
    )

    return DefaultInfo(files = depset([output_makefiles]))

makefiles = rule(
    implementation = _makefiles_impl,
    doc = "Generate `Makefile` and `Kbuild` files for `ddk_module`",
    attrs = {
        # module_X is the X attribute of the ddk_module. Prefixed with `module_`
        # because they aren't real srcs / hdrs / deps to the makefiles rule.
        "module_srcs": attr.label_list(allow_files = True),
        "module_hdrs": attr.label_list(providers = [DdkHeadersInfo]),
        "module_exported_hdrs": attr.label_list(providers = [DdkHeadersInfo]),
        "module_deps": attr.label_list(providers = [ModuleSymversInfo, DdkHeadersInfo]),
        "module_out": attr.string(),
        "_gen_makefile": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/gen_makefiles",
            executable = True,
            cfg = "exec",
        ),
    },
)
