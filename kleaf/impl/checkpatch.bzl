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

"""Rules to run checkpatch."""

visibility("//build/kernel/kleaf/...")

def _checkpatch_internal_impl(ctx):
    hermetic_tools = hermetic_toolchains.get(ctx)
    script_file = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))
    script = """#!/bin/bash -e
        # git is not part of hermetic tools. Work around it.
        GIT=$(command -v git)

        {run_setup}

        CHECKPATCH_PL={checkpatch_pl}
        {checkpatch_sh} "$@"
    """.format(
        run_setup = hermetic_tools.setup,
        checkpatch_pl = ctx.file.checkpatch_pl.short_path,
        checkpatch_sh = ctx.executable.checkpatch_sh.short_path,
    )

    ctx.actions.write(script_file, script, is_executable = True)

    runfiles = ctx.runfiles(
        files = [
            ctx.executable.checkpatch_sh,
            ctx.file.checkpatch_pl,
        ],
        transitive_files = depset(transitive = [
            hermetic_tools.deps,
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

_checkpatch_internal = rule(
    implementation = _checkpatch_internal_impl,
    doc = "common rule for `checkpatch*`",
    attrs = {
        "checkpatch_pl": attr.label(
            doc = "Label to `checkpatch.pl`",
            mandatory = True,
            allow_single_file = True,
        ),
        "checkpatch_sh": attr.label(
            doc = "Label to wrapper script",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [hermetic_toolchains.type],
)

def checkpatch_presubmit(
        name,
        tool,
        **kwargs):
    """Run `checkpatch_presubmit.sh` at the root of this package.

    Args:
        name: name of the target
        tool: Label to `checkpatch.pl`,
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    _checkpatch_internal(
        name = name,
        checkpatch_pl = tool,
        checkpatch_sh = Label("//build/kernel/static_analysis:checkpatch_presubmit"),
        **kwargs
    )

def checkpatch(
        name,
        tool,
        **kwargs):
    """Run `checkpatch.sh` at the root of this package.

    Args:
        name: name of the target
        tool: Label to `checkpatch.pl`,
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    _checkpatch_internal(
        name = name,
        checkpatch_pl = tool,
        checkpatch_sh = Label("//build/kernel/static_analysis:checkpatch"),
        **kwargs
    )
