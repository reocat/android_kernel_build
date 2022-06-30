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

# Test kernel_config against options (e.g. lto).
# Require //common package.

load("//build/kernel/kleaf:kernel.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load(":lto_transition.bzl", "lto_transition")
load(":kernel_config_aspect.bzl", "KernelConfigAspectInfo", "kernel_config_aspect")

def _lto_test_data_impl(ctx):
    files = []
    for lto, kernel_build in ctx.split_attr.kernel_build.items():
        kernel_config = kernel_build[KernelConfigAspectInfo].kernel_config
        config_file = utils.find_file(".config", kernel_config.files.to_list(), "{}: kernel_config outputs".format(kernel_build.label))

        # Create symlink so that the Python test script can infer the LTO setting
        # from the file name.
        copied = ctx.actions.declare_file("{}/{}_config".format(ctx.label.name, lto))
        ctx.actions.symlink(output = copied, target_file = config_file)
        files.append(copied)

    return DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files))

_lto_test_data = rule(
    implementation = _lto_test_data_impl,
    attrs = {
        "kernel_build": attr.label(cfg = lto_transition, aspects = [kernel_config_aspect]),
        "test_bin": attr.label(executable = True, cfg = "exec", allow_files = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _lto_test(name):
    kernel_build(
        name = name + "_kernel_build",
        srcs = ["//common:kernel_aarch64_sources"],
        outs = [],
        build_config = "//common:build.config.gki.aarch64",
        tags = ["manual"],
    )
    _lto_test_data(
        name = name + "_actual",
        kernel_build = name + "_kernel_build",
        test_bin = name + "_bin",
    )
    native.filegroup(
        name = name + "_expected",
        srcs = native.glob(["data/kernel_config_option_test/*"]),
    )
    native.py_test(
        name = name,
        python_version = "PY3",
        main = "contain_lines_test.py",
        srcs = ["contain_lines_test.py"],
        data = [
            name + "_expected",
            name + "_actual",
        ],
        args = [
            "--actual",
            "$(locations {}_actual)".format(name),
            "--expected",
            "$(locations {}_expected)".format(name),
        ],
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
    )

def kernel_config_option_test_suite(name):
    _lto_test(
        name = name + "_lto_test",
    )
    native.test_suite(
        name = name,
        tests = [
            name + "_lto_test",
        ],
    )
