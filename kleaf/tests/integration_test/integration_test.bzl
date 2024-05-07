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

"""Rules to run integration_test."""

load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")

def _integration_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script_file = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))
    script = """#!/bin/bash -e

        {run_additional_setup}

        {integration_test_bin} "$@"
    """.format(
        run_additional_setup = hermetic_tools.run_additional_setup,
        integration_test_bin = ctx.executable.integration_test_bin.short_path,
    )

    ctx.actions.write(script_file, script, is_executable = True)

    runfiles = ctx.runfiles(transitive_files = depset(transitive = [
        hermetic_tools.deps,
    ])).merge_all([
        ctx.attr.integration_test_bin[DefaultInfo].default_runfiles,
    ])

    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

_integration_test_internal_rule = rule(
    doc = "Run `integration_test.sh` at the root of this package.",
    implementation = _integration_test_impl,
    attrs = {
        "integration_test_bin": attr.label(
            doc = "Test binary",
            executable = True,
            cfg = "exec",
        ),
        "deps": attr.label_list(),
    },
    toolchains = [hermetic_toolchain.type],
    executable = True,
)

def integration_test(
        name,
        src,
        deps = None,
        **kwargs):
    """Kleaf integration test.

    Args:
        name: name of the test
        src: test script
        deps: deps of test script
        **kwargs: additional kwargs to internal rule
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    native.py_binary(
        name = name + "_bin",
        srcs = [src],
        main = src,
        deps = deps,
        **private_kwargs
    )

    _integration_test_internal_rule(
        name = name,
        integration_test_bin = name + "_bin",
        deps = deps,
        **kwargs
    )
