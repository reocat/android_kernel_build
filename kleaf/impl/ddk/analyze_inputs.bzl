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

def _analyze_inputs_transition_impl(settings, attr):
    if settings["//build/kernel/kleaf:config_local"]:
        print("\nWARNING: for {}, ignoring --config=local and enabling sandbox to analyze inputs.".format(attr.name))
    return {
        "//build/kernel/kleaf:preserve_cmd": True,
        # Require sandbox to avoid grabbing unrelated .cmd files
        "//build/kernel/kleaf:config_local": False,
    }

_analyze_inputs_transition = transition(
    implementation = _analyze_inputs_transition_impl,
    inputs = [
        "//build/kernel/kleaf:config_local",
    ],
    outputs = [
        "//build/kernel/kleaf:preserve_cmd",
        "//build/kernel/kleaf:config_local",
    ],
)

def _analyze_to_raw_paths(ctx):
    dirs = depset(transitive = [target[KernelCmdsInfo].directories for target in ctx.attr.deps])
    input_archives = depset(transitive = [t.files for t in ctx.attr.input_archives])

    raw_paths = ctx.actions.declare_file("{}/raw_paths.txt".format(ctx.label.name))

    args = ctx.actions.args()
    args.add_all("--include_filters", ctx.attr.include_filters)
    args.add_all("--exclude_filters", ctx.attr.exclude_filters)
    args.add_all("--input_archives", input_archives)
    args.add("--out", raw_paths)
    args.add_all("--dirs", dirs, expand_directories = False)

    ctx.actions.run(
        mnemonic = "AnalyzeInputs",
        inputs = depset(transitive = [dirs, input_archives]),
        outputs = [raw_paths],
        executable = ctx.executable._analyze_inputs,
        arguments = [args],
    )
    return raw_paths

def _create_sanitize_script(ctx, raw_paths):
    executable = ctx.actions.declare_file("{name}/{name}.sh".format(name = ctx.label.name))
    content = """#!/bin/bash -e
                 {sanitize_inputs} --input {raw_paths} $@
                 """.format(
        sanitize_inputs = shell.quote(ctx.executable._sanitize_inputs.short_path),
        raw_paths = shell.quote(raw_paths.short_path),
    )
    ctx.actions.write(executable, content, is_executable = True)

    runfiles = ctx.runfiles(files = [raw_paths])
    transitive_runfiles = [ctx.attr._sanitize_inputs[DefaultInfo].default_runfiles]
    runfiles = runfiles.merge_all(transitive_runfiles)

    return DefaultInfo(
        files = depset([executable]),
        executable = executable,
        runfiles = runfiles,
    )

def _analyze_inputs_impl(ctx):
    raw_paths = _analyze_to_raw_paths(ctx)
    default_info = _create_sanitize_script(ctx, raw_paths)
    return default_info

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
    cfg = _analyze_inputs_transition,
    attrs = {
        "deps": attr.label_list(
            providers = [KernelCmdsInfo],
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
        ),
        "_analyze_inputs": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/analyze_inputs",
            executable = True,
            cfg = "exec",
        ),
        "_sanitize_inputs": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/sanitize_inputs",
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
