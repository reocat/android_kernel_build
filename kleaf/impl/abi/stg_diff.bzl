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
        ctx.files.generated[0],
        ctx.file.reference,
        ctx.file.tool,
    ]

    error_msg = ctx.actions.declare_file("{}/error_msg.txt".format(ctx.attr.name))
    exit_code = ctx.actions.declare_file("{}/exit_code.txt".format(ctx.attr.name))

    outputs = []
    stgdiff_outputs_args = ""
    short_report = None
    for ext in ctx.attr.reporting_formats:
        report = ctx.actions.declare_file("{}/abi.report.{}".format(ctx.attr.name, ext))
        stgdiff_outputs_args += " --format {ext} --output {report}".format(
            ext = ext,
            report = report.path,
        )
        if ext == "short":
            short_report = report
        outputs.append(report)

    command_outputs = outputs + [
        error_msg,
        exit_code,
    ]
    command = """
        set +e
        {stgdiff} --stg {reference} {generated} {stgdiff_outputs_args} > {error_msg}  2>&1
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
        exit $rc
    """.format(
        change_code = STGDIFF_CHANGE_CODE,
        error_msg = error_msg.path,
        exit_code = exit_code.path,
        generated = ctx.files.generated[0].path,
        label = ctx.label,
        reference = ctx.file.reference.path,
        short_report = short_report.path,
        stgdiff = ctx.file.tool.path,
        stgdiff_outputs_args = stgdiff_outputs_args,
    )

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        mnemonic = "StgAbiDiff",
        progress_message = "[stg] Comparing ABI {}".format(ctx.label),
    )

    script = ctx.actions.declare_file("{}/print_results.sh".format(ctx.attr.name))
    script_content = """#!/bin/bash -e
        rc=$(cat {exit_code})
        if [[ $rc == {change_code} ]]; then
            echo "INFO: ABI DIFFERENCES HAVE BEEN DETECTED!"
            # echo "INFO: $(cat {short_report})"
        elif [[ $rc != 0 ]]; then
            echo "ERROR: $(cat {error_msg})" >&2
        fi
        exit $rc
""".format(
        change_code = STGDIFF_CHANGE_CODE,
        error_msg = error_msg.short_path,
        exit_code = exit_code.short_path,
        short_report = short_report.short_path,
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
            mandatory = True,
        ),
        "generated": attr.label(
            doc = "STG produced ABI representation.",
            mandatory = True,
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
            mandatory = True,
        ),
    },
    executable = True,
)
