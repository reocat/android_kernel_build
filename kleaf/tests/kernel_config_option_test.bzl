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

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")
load("//build/kernel/kleaf:kernel.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load(":contain_lines_test.bzl", "contain_lines_test")
load(":lto_transition.bzl", "lto_transition")
load(":kernel_config_aspect.bzl", "KernelConfigAspectInfo", "kernel_config_aspect")

def _lto_test_data_impl(ctx):
    files = []
    for lto, kernel_build in ctx.split_attr.kernel_build.items():
        kernel_config = kernel_build[KernelConfigAspectInfo].kernel_config
        config_file = utils.find_file(
            name = ".config",
            files = kernel_config.files.to_list(),
            what = "{}: kernel_config outputs".format(kernel_build.label),
        )

        # Create symlink so that the Python test script compares with the correct expected file.
        symlink = ctx.actions.declare_file("{}/{}_config".format(ctx.label.name, lto))
        ctx.actions.symlink(output = symlink, target_file = config_file)
        files.append(symlink)

    return DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files))

_lto_test_data = rule(
    implementation = _lto_test_data_impl,
    attrs = {
        "kernel_build": attr.label(cfg = lto_transition, aspects = [kernel_config_aspect]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _lto_test(name):
    """Test the effect of `--lto` on `kernel_config`."""
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
    )
    native.filegroup(
        name = name + "_expected",
        srcs = ["data/kernel_config_option_test/{}_config".format(lto) for lto in LTO_VALUES],
    )
    contain_lines_test(
        name = name,
        expected = name + "_expected",
        actual = name + "_actual",
    )

def _get_config_impl(ctx):
    kernel_config = ctx.attr.kernel_build[KernelConfigAspectInfo].kernel_config
    config_file = utils.find_file(
        name = ".config",
        files = kernel_config.files.to_list(),
        what = "{}: kernel_config outputs".format(ctx.attr.kernel_build.label),
    )

    # Create symlink so that the Python test script compares with the correct expected file.
    symlink = ctx.actions.declare_file("{}/{}_config".format(ctx.label.name, ctx.attr.prefix))
    ctx.actions.symlink(output = symlink, target_file = config_file)

    return DefaultInfo(files = depset([symlink]), runfiles = ctx.runfiles(files = [symlink]))

_get_config = rule(
    implementation = _get_config_impl,
    attrs = {
        "kernel_build": attr.label(aspects = [kernel_config_aspect], mandatory = True),
        "prefix": attr.string(),
    },
)

def _trim_test(name):
    """Test the effect of `trim_nonlisted_kmi` on `kernel_config`."""
    tests = []
    for trim in (True, False):
        prefix = "trim" if trim else "notrim"
        test_name = "{name}_{prefix}".format(name = name, prefix = prefix)
        kernel_build_name = "{test_name}_kernel_build".format(test_name = test_name)
        config_name = "{test_name}_actual".format(test_name = test_name)

        kernel_build(
            name = kernel_build_name,
            srcs = ["//common:kernel_aarch64_sources"],
            outs = [],
            build_config = "//common:build.config.gki.aarch64",
            trim_nonlisted_kmi = trim,
            kmi_symbol_list = "data/kernel_config_option_test/fake_kmi_symbol_list",
            tags = ["manual"],
        )
        _get_config(
            name = config_name,
            prefix = prefix,
            kernel_build = kernel_build_name,
        )
        contain_lines_test(
            name = test_name,
            expected = "data/kernel_config_option_test/{}_config".format(prefix),
            actual = config_name,
        )
        tests.append(test_name)
    native.test_suite(
        name = name,
        tests = tests,
    )

def _combined_option_test(name):
    """Test the effect of all of the following on `kernel_config`:

    - `--lto`
    - `trim_nonlisted_kmi`
    """
    tests = []
    for trim in (True, False):
        prefix = "trim" if trim else "notrim"
        test_name = "{name}_{prefix}".format(name = name, prefix = prefix)

        kernel_build(
            name = test_name + "_kernel",
            srcs = ["//common:kernel_aarch64_sources"],
            outs = [],
            build_config = "//common:build.config.gki.aarch64",
            trim_nonlisted_kmi = trim,
            kmi_symbol_list = "data/kernel_config_option_test/fake_kmi_symbol_list",
            tags = ["manual"],
        )

        # Test that it contains the proper LTO setting.
        _lto_test_data(
            name = test_name + "_lto_actual",
            kernel_build = test_name + "_kernel",
        )
        native.filegroup(
            name = test_name + "_lto_expected",
            srcs = ["data/kernel_config_option_test/{}_config".format(lto) for lto in LTO_VALUES],
        )
        contain_lines_test(
            name = test_name + "_has_lto",
            expected = test_name + "_lto_expected",
            actual = test_name + "_lto_actual",
        )
        tests.append(test_name + "_has_lto")

        # Test that it contains the proper trim setting.
        _get_config(
            name = test_name + "_config",
            prefix = prefix,
            kernel_build = test_name + "_kernel",
        )
        contain_lines_test(
            name = test_name + "_has_trim",
            expected = "data/kernel_config_option_test/{}_config".format(prefix),
            actual = test_name + "_config",
        )
        tests.append(test_name + "_has_trim")

    native.test_suite(
        name = name,
        tests = tests,
    )

def kernel_config_option_test_suite(name):
    unittest.suite(
        name,
        _lto_test,
        _trim_test,
        _combined_option_test,
    )
