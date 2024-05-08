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

def _hermetic_py_impl(ctx):
    test_hermetic_tools = hermetic_toolchain.get(ctx, for_tests = True)
    script_file = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))

    if ctx.attr.append_host_path:
        run_setup = test_hermetic_tools.run_additional_setup
    else:
        run_setup = test_hermetic_tools.run_setup

    script = """#!/bin/bash -e
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

_hermetic_py_test = rule(
    implementation = _hermetic_py_impl,
    attrs = {
        "actual": attr.label(
            executable = True,
            cfg = "exec",
        ),
        "append_host_path": attr.bool(),
        "data": attr.label_list(allow_files = True),
    },
    toolchains = [hermetic_toolchain.type],
    test = True,
)

def hermetic_py_test(
        name,
        main,
        append_host_path = None,
        srcs = None,
        deps = None,
        data = None,
        args = None,
        timeout = None,
        **kwargs):
    """Replacement for py_binary with necessary toolchains.

    Args:
        name: name of the test
        append_host_path: If true, append host PATH to the end of PATH.
            Breaks hermeticity.
        srcs: [py_binary.srcs](https://bazel.build/reference/be/python#py_binary.srcs)
        main: [py_binary.main](https://bazel.build/reference/be/python#py_binary.main)
        deps: [py_binary.deps](https://bazel.build/reference/be/python#py_binary.deps)
        data: [py_binary.data](https://bazel.build/reference/be/python#py_binary.data)
        args: [py_binary.args](https://bazel.build/reference/be/python#py_binary.args)
        timeout: [py_binary.timeout](https://bazel.build/reference/be/python#py_binary.timeout)
        **kwargs: Additional attributes to the internal rule, e.g.
            [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
            See complete list
            [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    native.py_test(
        name = name + "_bin",
        srcs = srcs,
        main = main,
        deps = deps,
        timeout = timeout,
        **private_kwargs
    )

    _hermetic_py_test(
        name = name,
        actual = name + "_bin",
        append_host_path = append_host_path,
        data = data,
        args = args,
        **kwargs
    )
