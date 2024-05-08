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

"""Rules that wraps a py_test / py_binary (for test purposes) so it is more hermetic."""

load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")

def _hermetic_test_impl(ctx):
    test_hermetic_tools = hermetic_toolchain.get(ctx, for_tests = True)
    script_file = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))

    if ctx.attr.append_host_path:
        run_setup = test_hermetic_tools.run_additional_setup
    else:
        run_setup = test_hermetic_tools.run_setup

    script = """#!/bin/bash -ex
        {run_setup}
        {actual} "$@"
    """.format(
        run_setup = run_setup,
        actual = ctx.executable.actual.short_path,
    )

    ctx.actions.write(script_file, script, is_executable = True)

    runfiles_transitive_files = [
        test_hermetic_tools.deps,
    ]
    transitive_runfiles = [
        ctx.attr.actual[DefaultInfo].default_runfiles,
    ]
    for target in ctx.attr.data:
        runfiles_transitive_files.append(target.files)
        transitive_runfiles.append(target[DefaultInfo].default_runfiles)

    runfiles = ctx.runfiles(transitive_files = depset(transitive = runfiles_transitive_files))
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

_RULE_ATTRS = dict(
    doc = "Wraps a test binary so it runs with hermetic tools.",
    implementation = _hermetic_test_impl,
    attrs = {
        "actual": attr.label(
            doc = "Actual test binary",
            executable = True,
            # Avoids transition on the test binary. The user is responsible
            # for handling any host platform transitions.
            # This has no effect, but it is required if executable = True.
            cfg = "target",
        ),
        "append_host_path": attr.bool(doc = """
            If true, append host PATH to the end of PATH.
            Breaks hermeticity.
        """),
        "data": attr.label_list(allow_files = True, doc = """
            See [data](https://bazel.build/reference/be/common-definitions#typical.data)
        """),
    },
    toolchains = [hermetic_toolchain.type],
)

hermetic_test = rule(test = True, **_RULE_ATTRS)
hermetic_test_binary = rule(executable = True, **_RULE_ATTRS)
