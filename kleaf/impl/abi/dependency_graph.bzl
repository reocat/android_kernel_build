# Copyright (C) 2024 The Android Open Source Project
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

"""Extracts symbols from kernel binaries."""

load(":abi/abi_transitions.bzl", "abi_common_attrs", "notrim_transition")
load(
    ":common_providers.bzl",
    "KernelBuildAbiInfo",
    "KernelModuleInfo",
    "KernelSerializedEnvInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

def _dependency_graph_extractor_impl(ctx):
    out = ctx.actions.declare_file("{}/dependency_graph.json".format(ctx.attr.name))
    intermediates_dir = utils.intermediates_dir(ctx)
    vmlinux = utils.find_file(
        name = "vmlinux",
        files = ctx.files.kernel_build,
        what = "{}: kernel_build".format(
            ctx.attr.name,
        ),
        required = True,
    )
    in_tree_modules = utils.find_files(suffix = ".ko", files = ctx.files.kernel_build)
    srcs = [vmlinux]
    srcs += in_tree_modules

    # external modules
    for kernel_module in ctx.attr.kernel_modules:
        if KernelModuleInfo in kernel_module:
            srcs += kernel_module[KernelModuleInfo].files.to_list()
        else:
            srcs += kernel_module.files.to_list()

    inputs = [] + srcs
    transitive_inputs = [ctx.attr.kernel_build[KernelSerializedEnvInfo].inputs]
    tools = [ctx.executable._dependency_graph_extractor]
    transitive_tools = [ctx.attr.kernel_build[KernelSerializedEnvInfo].tools]

    # Get the signed and stripped module archive for the GKI modules
    base_modules_archive = ctx.attr.kernel_build[KernelBuildAbiInfo].base_modules_staging_archive
    if not base_modules_archive:
        base_modules_archive = ctx.attr.kernel_build[KernelBuildAbiInfo].modules_staging_archive
    inputs.append(base_modules_archive)

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = ctx.attr.kernel_build[KernelSerializedEnvInfo],
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += """
        mkdir -p {intermediates_dir}
        # Extract archive and copy the modules from the base kernel first.
        mkdir -p {intermediates_dir}/temp
        tar xf {base_modules_archive} -C {intermediates_dir}/temp
        find {intermediates_dir}/temp -name '*.ko' -exec mv -t {intermediates_dir} {{}} \\;
        rm -rf {intermediates_dir}/temp
        # Copy other inputs including vendor modules;
        cp -pfl {srcs} {intermediates_dir}
        {dependency_graph_extractor} {intermediates_dir} {output}
        rm -rf {intermediates_dir}
    """.format(
        srcs = " ".join([file.path for file in srcs]),
        intermediates_dir = intermediates_dir,
        dependency_graph_extractor = ctx.executable._dependency_graph_extractor.path,
        output = out.path,
        base_modules_archive = base_modules_archive.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out],
        command = command,
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Obtaining dependency graph {}".format(ctx.label),
        mnemonic = "KernelDependencyGraphExtractor",
    )

    return DefaultInfo(files = depset([out]))

dependency_graph_extractor = rule(
    implementation = _dependency_graph_extractor_impl,
    attrs = {
        "kernel_build": attr.label(providers = [KernelSerializedEnvInfo, KernelBuildAbiInfo]),
        "kernel_modules": attr.label_list(allow_files = True),
        "_dependency_graph_extractor": attr.label(
            default = "//build/kernel:dependency_graph_extractor",
            cfg = "exec",
            executable = True,
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | abi_common_attrs(),
    cfg = notrim_transition,
)

def _dependency_graph_drawer_impl(ctx):
    out = ctx.actions.declare_file("{}/dependency_graph.dot".format(ctx.attr.name))
    input = ctx.file.adjacency_list
    tool = ctx.executable._dependency_graph_drawer
    command = """
        {dependency_graph_drawer} {input} {output}
    """.format(
        input = input.path,
        dependency_graph_drawer = tool.path,
        output = out.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = depset([input]),
        outputs = [out],
        command = command,
        tools = depset([ctx.executable._dependency_graph_drawer]),
        progress_message = "Drawing a dependency graph {}".format(ctx.label),
        mnemonic = "KernelDependencyGraphDrawer",
    )

    return DefaultInfo(files = depset([out]))

dependency_graph_drawer = rule(
    implementation = _dependency_graph_drawer_impl,
    attrs = {
        "adjacency_list": attr.label(allow_single_file = True, mandatory = True),
        "_dependency_graph_drawer": attr.label(
            default = "//build/kernel:dependency_graph_drawer",
            cfg = "exec",
            executable = True,
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
