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

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":analyze_inputs.bzl", "analyze_inputs")

def _ddk_headers_target_generator_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    content = """#!/bin/bash -e
                 {input_script} | \
                 {generator} $@
                 """.format(
        input_script = shell.quote(ctx.executable.input_script.short_path),
        generator = shell.quote(ctx.executable._generator.short_path),
    )
    ctx.actions.write(executable, content, is_executable = True)

    runfiles = ctx.runfiles()
    transitive_runfiles = [
        ctx.attr.input_script[DefaultInfo].default_runfiles,
        ctx.attr._generator[DefaultInfo].default_runfiles,
    ]
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([executable]),
        executable = executable,
        runfiles = runfiles,
    )

_ddk_headers_target_generator = rule(
    implementation = _ddk_headers_target_generator_impl,
    attrs = {
        "input_script": attr.label(executable = True, cfg = "exec"),
        "_generator": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/ddk_headers_target_generator",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
)

def analyze_ddk_headers(
        name,
        deps,
        input_archives = None):
    """Defines an executable target that generates buildozer commands to generate `ddk_headers` targets.

    Example:
    ```
    analyze_ddk_headers(
        name = "tuna_input_headers",
        deps = [
            ":tuna",
        ] + _TUNA_EXT_MODULES, # The list of external kernel_module()'s.
    )
    ```

    """
    if input_archives == None:
        input_archives = [
            # Ignore device-specific UAPI headers for now.
            "//common:kernel_aarch64_uapi_headers",
            "//common:kernel_aarch64_script_headers",
        ]

    analyze_inputs(
        name = name + "_headers_list",
        exclude_filters = [
            "arch/arm64/include/generated/*",
            "include/generated/*",
        ],
        include_filters = ["*.h"],
        input_archives = input_archives,
        deps = deps,
    )

    _ddk_headers_target_generator(
        name = name,
        input_script = name + "_headers_list",
    )
