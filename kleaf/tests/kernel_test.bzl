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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _write_script_and_arguments(ctx, arguments):
    if ctx.attr._config[BuildSettingInfo].value != "release":
        ctx.actions.write(content = "", output = ctx.outputs.executable, is_executable = True)
        return []

    arguments_file = ctx.actions.declare_file("{}.args".format(ctx.attr.name))
    ctx.actions.write(
        output = arguments_file,
        content = arguments,
    )
    ctx.actions.expand_template(
        template = ctx.file._script,
        output = ctx.outputs.executable,
        substitutions = {
            "{arguments_file}": arguments_file.short_path,
        },
        is_executable = True,
    )
    return [arguments_file]

def _kernel_module_test_impl(ctx):
    arguments = " ".join([f.short_path for f in ctx.files.modules])
    runfiles = _write_script_and_arguments(ctx, arguments)
    return [DefaultInfo(runfiles = ctx.runfiles(files = ctx.files.modules + runfiles))]

kernel_module_test = rule(
    doc = "A test on artifacts produced by [kernel_module](#kernel_module).",
    implementation = _kernel_module_test_impl,
    attrs = {
        "modules": attr.label_list(allow_files = True),
        "_script": attr.label(default = "//build/kernel/kleaf/tests:kernel_module_test.py", allow_single_file = True),
        "_config": attr.label(default = "//build/kernel/kleaf:config"),
    },
    test = True,
)

def _kernel_build_test_impl(ctx):
    arguments = " ".join([f.short_path for f in ctx.files.target])
    runfiles = _write_script_and_arguments(ctx, arguments)
    return [DefaultInfo(runfiles = ctx.runfiles(files = ctx.files.target + runfiles))]

kernel_build_test = rule(
    doc = "A test on artifacts produced by [kernel_build](#kernel_build).",
    implementation = _kernel_build_test_impl,
    attrs = {
        "target": attr.label(doc = "The [`kernel_build()`](#kernel_build).", allow_files = True),
        "_script": attr.label(default = "//build/kernel/kleaf/tests:kernel_build_test.py", allow_single_file = True),
        "_config": attr.label(default = "//build/kernel/kleaf:config"),
    },
    test = True,
)
