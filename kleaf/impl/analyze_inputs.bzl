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
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":common_providers.bzl", "KernelBuildUapiInfo", "KernelCmdsInfo")

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
    # Require sandbox to avoid grabbing unrelated .cmd files
    if ctx.attr._config_is_local[BuildSettingInfo].value:
        fail("{}: requires that --config=local is not set.".format(ctx.label))

    dirs = [target[KernelCmdsInfo].directory for target in ctx.attr.deps]
    input_archives = ctx.files.input_archives

    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    content = """#!/bin/bash -e
                 {analyze_inputs} \
                   --include_filters {include_filters} \
                   --exclude_filters {exclude_filters} \
                   --dirs {dirs} \
                   --input_archives {input_archives} \
                   $@
                 """.format(
        analyze_inputs = shell.quote(ctx.executable._analyze_inputs.short_path),
        include_filters = " ".join([shell.quote(filter) for filter in ctx.attr.include_filters]),
        exclude_filters = " ".join([shell.quote(filter) for filter in ctx.attr.exclude_filters]),
        input_archives = " ".join([shell.quote(archive.short_path) for archive in input_archives]),
        dirs = " ".join([shell.quote(d.short_path) for d in dirs]),
    )
    ctx.actions.write(executable, content, is_executable = True)

    runfiles = ctx.runfiles(files = dirs + input_archives)
    transitive_runfiles = [ctx.attr._analyze_inputs[DefaultInfo].default_runfiles]
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([executable]),
        executable = executable,
        runfiles = runfiles,
    )

analyze_inputs = rule(
    doc = """Analyze the inputs from the list of `.cmd` files

Example:

```
analyze_inputs(
    name = "tuna_input_headers",
    exclude_filters = [
        "arch/arm64/include/generated/*",
        "include/generated/*",
    ],
    include_filters = ["*.h"],
    input_archives = [
        "//common:kernel_aarch64_uapi_headers", # or merged_kernel_uapi_headers
        "//common:kernel_aarch64_script_headers",
    ],
    deps = [
        ":tuna",
    ] + _TUNA_EXT_MODULES, # The list of external kernel_module()'s.
)
```

""",
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
        "input_archives": attr.label_list(
            allow_files = [".tar", ".tar.gz"],
            doc = """A list of archives which serves as additional inputs.
                     If an input in the `.cmd` file is found in these archives, the input
                     is considered resolved.""",
            # Technically these archives don't need the transition, but to avoid explosion of
            # targets, do the transition for all inputs.
            cfg = _preserve_cmd_transition,
        ),
        "_analyze_inputs": attr.label(
            default = "//build/kernel/kleaf/impl:analyze_inputs",
            executable = True,
            cfg = "exec",
        ),
        "_config_is_local": attr.label(default = "//build/kernel/kleaf:config_local"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
)
