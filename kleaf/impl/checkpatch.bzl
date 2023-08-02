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

"""Run checkpatch.sh against `KERNEL_DIR`"""

load(":common_providers.bzl", "KernelEnvInfo")

visibility("//build/kernel/kleaf/...")

def _impl(ctx):
    script_file = ctx.actions.declare_file(
        "{}/{}".format(ctx.attr.name, "checkpatch.sh"),
    )

    script = """#!/bin/bash -e

        # git is not part of hermetic tools. Work around it.
        GIT=$(command -v git)
        {run_setup}
        PATH=$PATH:$(dirname ${{GIT}})

        FORWARDED_ARGS=()
        while [[ $# -gt 0 ]]; do
            next="$1"
            case ${{next}} in
                --dist_dir)
                    export DIST_DIR="$2"
                    shift
                    shift
                    ;;
                --dist_dir=*)
                    export DIST_DIR="${{next#*=}}"
                    shift
                    ;;
                *)
                    FORWARDED_ARGS+=("$1")
                    shift
                    ;;
            esac
        done

        if [[ ${{DIST_DIR}} != /* ]]; then
            DIST_DIR=${{BUILD_WORKSPACE_DIRECTORY}}/${{DIST_DIR}}
        fi

        {real_checkpatch} ${{FORWARDED_ARGS[*]}}
""".format(
        run_setup = ctx.attr.env[KernelEnvInfo].run_env.setup,
        real_checkpatch = ctx.executable._checkpatch_sh.short_path,
    )

    ctx.actions.write(script_file, script, is_executable = True)

    runfiles = ctx.runfiles(
        files = [ctx.executable._checkpatch_sh],
        transitive_files = depset(transitive = [
            ctx.attr.env[KernelEnvInfo].run_env.inputs,
            ctx.attr.env[KernelEnvInfo].run_env.tools,
        ]),
    )
    transitive_runfiles = [
        ctx.attr._checkpatch_sh[DefaultInfo].default_runfiles,
    ]
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

checkpatch = rule(
    doc = "Run checkpatch_presubmit.sh against `KERNEL_DIR`",
    implementation = _impl,
    attrs = {
        "env": attr.label(doc = "kernel_env", mandatory = True),
        "_checkpatch_sh": attr.label(
            default = "//build/kernel/static_analysis:checkpatch_presubmit",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
)
