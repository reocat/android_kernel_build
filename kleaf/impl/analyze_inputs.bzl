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
load(":common_providers.bzl", "KernelCmdsInfo")

def _preserve_cmd_transition_impl(settings, attr):
    _ignore = (settings, attr)
    return {
        "//build/kernel/kleaf:preserve_cmd": True,
    }

_preserve_cmd_transition = transition(
    implementation = _preserve_cmd_transition_impl,
    inputs = [],
    outputs = ["//build/kernel/kleaf:preserve_cmd"],
)

def _analyze_inputs_impl(ctx):
    dirs = [target[KernelCmdsInfo].directory for target in ctx.attr.deps]

    executable = ctx.actions.declare_file(ctx.label.name + ".sh")

    content = """#!/bin/bash -e
                 {analyze_inputs} \
                   --include_filters {include_filters} \
                   --exclude_filters {exclude_filters} \
                   --dirs {dirs} \
                   $@
                 """.format(
        analyze_inputs = shell.quote(ctx.executable._analyze_inputs.short_path),
        include_filters = " ".join([shell.quote(filter) for filter in ctx.attr.include_filters]),
        exclude_filters = " ".join([shell.quote(filter) for filter in ctx.attr.exclude_filters]),
        dirs = " ".join([shell.quote(d.short_path) for d in dirs]),
    )

    ctx.actions.write(executable, content, is_executable = True)

    runfiles = ctx.runfiles(files = dirs)
    transitive_runfiles = [ctx.attr._analyze_inputs[DefaultInfo].default_runfiles]
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([executable]),
        executable = executable,
        runfiles = runfiles,
    )

analyze_inputs = rule(
    doc = "Analyze the inputs from the list of `.cmd` files",
    implementation = _analyze_inputs_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [KernelCmdsInfo],
            cfg = _preserve_cmd_transition,
        ),
        "include_filters": attr.string_list(
            doc = "glob patterns that filters the output list",
        ),
        "exclude_filters": attr.string_list(
            doc = "glob patterns that filters out the output list",
        ),
        "_analyze_inputs": attr.label(
            default = "//build/kernel/kleaf/impl:analyze_inputs",
            executable = True,
            cfg = "exec",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
)
