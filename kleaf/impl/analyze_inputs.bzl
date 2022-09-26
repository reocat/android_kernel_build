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
    out = ctx.actions.declare_file("{}.txt".format(ctx.attr.name))

    args = ctx.actions.args()

    # Though flag_per_line is designed for the absl flags library and
    # gen_makefiles.py uses absl flags library, this outputs the following
    # in the output params file:
    #   --foo=value1 value2
    # ... which is interpreted as --foo="value1 value2" instead of storing
    # individual values. Hence, use multiline so the output becomes:
    #   --foo
    #   value1
    #   value2
    args.set_param_file_format("multiline")
    args.use_param_file("--flagfile=%s")

    args.add("--out", out)
    args.add("--pattern", ctx.attr.pattern)

    # If we add_all(dirs) here, all files under dirs are added. To reduce
    # the size of the parameters sent, just pass the root directory and
    # let the script discover the files.
    args.add_all("--dirs", [d.path for d in dirs])
    ctx.actions.run(
        outputs = [out],
        inputs = dirs,
        executable = ctx.executable._analyze_inputs,
        arguments = [args],
    )

    return DefaultInfo(
        files = depset([out]),
    )

analyze_inputs = rule(
    doc = "Analyze the inputs from the list of `.cmd` files",
    implementation = _analyze_inputs_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [KernelCmdsInfo],
            cfg = _preserve_cmd_transition,
        ),
        "pattern": attr.string(
            doc = "A glob pattern that filters the output list",
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
)
