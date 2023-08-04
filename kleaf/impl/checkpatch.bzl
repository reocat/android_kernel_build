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

load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _checkpatch_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script_file = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))
    script = """#!/bin/bash -e
        # git is not part of hermetic tools. Work around it.
        GIT=$(command -v git)

        {run_setup}

        {checkpatch_sh} \\
            --ignored_checks {ignorelist} \\
            --dir {dir} \\
            "$@" \\
            --checkpatch_pl {checkpatch_pl} \\
            --git ${{GIT}}
    """.format(
        run_setup = hermetic_tools.run_setup,
        checkpatch_pl = ctx.file.checkpatch_pl.short_path,
        checkpatch_sh = ctx.executable.checkpatch_sh.short_path,
        ignorelist = ctx.file.ignorelist.short_path,
        dir = ctx.label.package,
    )

    ctx.actions.write(script_file, script, is_executable = True)

    runfiles = ctx.runfiles(
        files = [
            ctx.executable.checkpatch_sh,
            ctx.file.checkpatch_pl,
            ctx.file.ignorelist,
        ],
        transitive_files = depset(transitive = [
            hermetic_tools.deps,
        ]),
    )
    transitive_runfiles = [
        ctx.attr.checkpatch_sh[DefaultInfo].default_runfiles,
    ]
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

_checkpatch = rule(
    implementation = _checkpatch_impl,
    doc = "common rule for `checkpatch*`",
    attrs = {
        "checkpatch_pl": attr.label(
            doc = "Label to `checkpatch.pl`",
            mandatory = True,
            allow_single_file = True,
        ),
        "ignorelist": attr.label(
            doc = "checkpatch ignorelist",
            allow_single_file = True,
            default = "//build/kernel/static_analysis:checkpatch_ignorelist",
        ),
        "checkpatch_sh": attr.label(
            doc = "Label to wrapper script",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [hermetic_toolchain.type],
    executable = True,
)

def checkpatch(
        name,
        checkpatch_pl,
        ignorelist = None,
        **kwargs):
    """Run `checkpatch.sh` at the root of this package.

    Args:
        name: name of the target
        checkpatch_pl: Label to `checkpatch.pl`.

          This is usually `//<common_package>:scripts/checkpatch.pl`.
        ignorelist: checkpatch ignorelist. Default is `//build/kernel/static_analysis:checkpatch_ignorelist`.
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    _checkpatch(
        name = name,
        checkpatch_pl = checkpatch_pl,
        ignorelist = ignorelist,
        checkpatch_sh = Label("//build/kernel/kleaf/impl:checkpatch"),
        **kwargs
    )
