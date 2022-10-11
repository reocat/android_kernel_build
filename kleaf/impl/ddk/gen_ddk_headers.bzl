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
load(":ddk/analyze_inputs.bzl", "analyze_inputs")
load(":common_providers.bzl", "KernelCmdsInfo")
load(":utils.bzl", "utils")

def _gen_ddk_headers_impl(ctx):
    intermediates = utils.intermediates_dir(ctx)
    executable = ctx.actions.declare_file(ctx.label.name + ".sh")

    # FIXME hermetic tools?
    content = """#!/bin/bash -e
                 mkdir -p {intermediates_dir}
                 {input_script} \
                    {intermediates_dir}/sanitized_paths.txt \
                    {intermediates_dir}/sanitized_includes.txt
                 {generator} \
                   --input {intermediates_dir}/sanitized_paths.txt \
                   --input_includes {intermediates_dir}/sanitized_includes.txt \
                   $@
                 """.format(
        intermediates_dir = intermediates,
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

_gen_ddk_headers = rule(
    implementation = _gen_ddk_headers_impl,
    attrs = {
        "input_script": attr.label(executable = True, cfg = "exec"),
        "_generator": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/gen_ddk_headers",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
)

def gen_ddk_headers(
        name,
        target):
    # TODO make generic (without ref to //common)
    input_archives = [
        # Ignore device-specific UAPI headers for now.
        "//common:kernel_aarch64_uapi_headers",
        "//common:kernel_aarch64_script_headers",
    ]

    analyze_inputs(
        name = name + "_inputs",
        exclude_filters = [
            "arch/arm64/include/generated/*",
            "include/generated/*",
        ],
        include_filters = ["*.h"],
        input_archives = input_archives,
        deps = [target],
    )

    _gen_ddk_headers(
        name = name,
        input_script = name + "_inputs",
    )
