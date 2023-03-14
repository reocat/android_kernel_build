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

"""Extracts ABI information."""

def _stgextract_impl(ctx):
    args = []
    abi_out_file = ctx.actions.declare_file("{}/abi.stg".format(ctx.attr.name))
    args.append("--output {abi_out_file}".format(abi_out_file = abi_out_file.path))

    inputs = [ctx.file.tool]
    if ctx.file.symbol_filter:
        args.append("--symbols :{symbol_filter}".format(
            symbol_filter = ctx.file.symbol_filter.path,
        ))
        inputs.append(ctx.file.symbol_filter)

    # Separate sources based on their file extension.
    binaries = []
    stg_definition = None
    for src in ctx.files.srcs:
        if src.basename.endswith(".stg"):
            stg_definition = src
        else:
            binaries.append(src)

    if stg_definition:
        args.append("--stg {stg_definition}".format(stg_definition.path))
        inputs.append(stg_definition)

    if binaries:
        args.append("--elf {binaries}".format(
            binaries = " ".join([binary.path for binary in binaries]),
        ))
        inputs += binaries

    command = "{stg} {args}".format(stg = ctx.file.tool.path, args = " ".join(args))
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [abi_out_file],
        command = command,
        mnemonic = "StgAbiExtract",
        progress_message = "[stg] Extracting ABI {}".format(ctx.label),
    )
    return [DefaultInfo(files = depset([abi_out_file]))]

stgextract = rule(
    implementation = _stgextract_impl,
    doc = """Invokes |stg| with all the *srcs to extract the ABI information.
      If a |symbol_filter| is suplied, symbols not maching the filter are
    dropped.

    It produces one {ctx.attr.name}.stg file.
    """,
    attrs = {
        "srcs": attr.label_list(
            doc = """Binaries with ELF information.
            And/or files with ABI information in stg format.""",
            allow_files = True,
        ),
        "symbol_filter": attr.label(
            doc = "File containing a symbol list.",
            allow_single_file = True,
        ),
        "tool": attr.label(
            doc = "stg binary",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
            mandatory = True,
        ),
    },
)
