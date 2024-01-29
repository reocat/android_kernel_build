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

"""Processes KMI symbols."""

load(":common_providers.bzl", "KernelEnvInfo")
load(":debug.bzl", "debug")

visibility("//build/kernel/kleaf/...")

def _kmi_symbol_list_impl(ctx):
    if not ctx.files.srcs:
        return []

    inputs = [] + ctx.files.srcs
    transitive_inputs = [ctx.attr.env[KernelEnvInfo].inputs]

    tools = [ctx.executable._process_symbols]
    transitive_tools = [ctx.attr.env[KernelEnvInfo].tools]

    outputs = []
    full_abi_out_file = ctx.actions.declare_file("{}/abi_symbollist".format(ctx.attr.name))
    stable_abi_out_file = ctx.actions.declare_file("{}/stable_abi_symbollist".format(ctx.attr.name))
    report_file = ctx.actions.declare_file("{}/abi_symbollist.report".format(ctx.attr.name))
    outputs = [full_abi_out_file, stable_abi_out_file, report_file]

    command = ctx.attr.env[KernelEnvInfo].setup + """
        mkdir -p {out_dir}
        {process_symbols} --out-dir={out_dir} --out-file={out_file_base} \
            --report-file={report_file_base} --in-dir="${{ROOT_DIR}}" \
            {srcs}
    """.format(
        process_symbols = ctx.executable._process_symbols.path,
        out_dir = full_abi_out_file.dirname,
        out_file_base = full_abi_out_file.basename,
        report_file_base = report_file.basename,
        srcs = " ".join([f.path for f in ctx.files.srcs]),
    )

    if ctx.files.unstable_kmi_symbol_list:
        inputs += ctx.files.unstable_kmi_symbol_list
        if len(ctx.files.unstable_kmi_symbol_list) > 1:
            fail("{}: ctx.files.unstable_kmi_symbol_list must only provide at most one file".format(ctx.label))
        unstable_kmi_symbol_list = ctx.files.unstable_kmi_symbol_list[0]

        # TODO: A more robust exclusion command is needed. This one requires the lines
        #       be exactly the same including the leading spaces.
        command += """
            grep -v -F -x -f {excluded_symbollist} {full_abi_out_file} > {stable_abi_out_file}
        """.format(
            excluded_symbollist = unstable_kmi_symbol_list.path,
            full_abi_out_file = full_abi_out_file.path,
            stable_abi_out_file = stable_abi_out_file.path,
        )
    else:
        command += """
            cp -p {full_abi_out_file} {stable_abi_out_file}
        """.format(
            full_abi_out_file = full_abi_out_file.path,
            stable_abi_out_file = stable_abi_out_file.path,
        )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KmiSymbolList",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = outputs,
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Creating abi_symbollist and report {}".format(ctx.label),
        command = command,
    )

    return [
        DefaultInfo(files = depset(outputs)),
        OutputGroupInfo(
            abi_symbollist = depset([full_abi_out_file]),
            stable_abi_symbollist = depset([stable_abi_out_file]),
	),
    ]

kmi_symbol_list = rule(
    implementation = _kmi_symbol_list_impl,
    doc = "Build `abi_symbollist` if there are `srcs`, otherwise don't build anything.",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(
            doc = "`KMI_SYMBOL_LIST` + `ADDITIONAL_KMI_SYMBOL_LISTS` + UNSTABLE_KMI_SYMBOL_LIST",
            allow_files = True,
        ),
        "unstable_kmi_symbol_list": attr.label(
            allow_single_file = True,
        ),
        "_process_symbols": attr.label(
            default = "//build/kernel:abi_process_symbols",
            cfg = "exec",
            executable = True,
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
