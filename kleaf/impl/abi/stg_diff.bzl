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

"""Compares two ABI definitions."""

STGDIFF_FORMATS = ["plain", "flat", "small", "short", "viz"]
STGDIFF_CHANGE_CODE = 4

def _stgdiff_impl(ctx):
    inputs = [
        ctx.file.generated,
        ctx.file.reference,
        ctx.file.tool,
    ]

    output_dir = ctx.actions.declare_directory("{}/abi_stgdiff".format(ctx.attr.name))
    error_msg = ctx.actions.declare_file("{}/error_msg.txt".format(ctx.attr.name))
    exit_code = ctx.actions.declare_file("{}/exit_code.txt".format(ctx.attr.name))

    outputs = [output_dir]
    command_outputs = outputs + [
        error_msg,
        exit_code,
    ]
    basename = "{output_dir}/abi.report".format(output_dir = output_dir.path)
    stgdiff_outputs = " ".join(["--format {ext} --output {basename}.{ext}".format(
        basename = basename,
        ext = ext,
    ) for ext in STGDIFF_FORMATS])
    short_report = basename + ".short"
    command = """
        set +e
        {stgdiff} --stg {reference} {generated} {stgdiff_outputs} > {error_msg}  2>&1
        rc=$?
        set -e
        echo $rc > {exit_code}
        if [[ $rc == {change_code} ]]; then
            echo "INFO: ABI DIFFERENCES HAVE BEEN DETECTED!" >&2
            echo "INFO: $(cat {short_report})" >&2
        elif [[ $rc != 0 ]]; then
            echo "ERROR: $(cat {error_msg})" >&2
            echo "INFO: exit code is not checked. 'tools/bazel run {label}' to check the exit code." >&2
        fi
    """.format(
        change_code = STGDIFF_CHANGE_CODE,
        error_msg = error_msg.path,
        exit_code = exit_code.path,
        generated = ctx.file.generated.path,
        label = ctx.label,
        output_dir = output_dir.path,
        reference = ctx.file.reference.path,
        short_report = short_report,
        stgdiff = ctx.file.tool.path,
        stgdiff_outputs = stgdiff_outputs,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        mnemonic = "StgAbiDiff",
        progress_message = "[stg] Comparing ABI {}".format(ctx.label),
    )

    script = ctx.actions.declare_file("{}/print_results.sh".format(ctx.attr.name))
    short_report = "{output_dir}/abi.report.short".format(output_dir = output_dir.short_path)
    script_content = """#!/bin/bash -e
        if [[ $rc == {change_code} ]]; then
            echo "INFO: ABI DIFFERENCES HAVE BEEN DETECTED!"
            echo "INFO: $(cat {short_report})"
        elif [[ $rc != 0 ]]; then
            echo "ERROR: $(cat {error_msg})" >&2
        fi
        exit $(cat {exit_code})
""".format(
        change_code = STGDIFF_CHANGE_CODE,
        error_msg = error_msg.short_path,
        exit_code = exit_code.short_path,
        short_report = short_report,
    )
    ctx.actions.write(script, script_content, is_executable = True)

    return [
        DefaultInfo(
            files = depset(outputs),
            executable = script,
            runfiles = ctx.runfiles(files = command_outputs),
        ),
        OutputGroupInfo(
            executable = depset([script]),
        ),
    ]

stgdiff = rule(
    implementation = _stgdiff_impl,
    doc = """Compares a |generated| ABI against a |reference|.""",
    attrs = {
        "reference": attr.label(
            doc = "STG baseline ABI representation.",
            allow_single_file = True,
        ),
        "generated": attr.label(
            doc = "STG produced ABI representation.",
        ),
        "reporting_formats": attr.string_list(
            doc = "Output formats.",
            default = STGDIFF_FORMATS,
        ),
        "tool": attr.label(
            doc = "stgdiff binary",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
    },
)
