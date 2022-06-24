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

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")
load("//build/kernel/kleaf:kernel.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load(":contain_lines_test.bzl", "contain_lines_test")
load(":kasan_transition.bzl", "kasan_transition")
load(":lto_transition.bzl", "lto_transition")
load(":kernel_config_aspect.bzl", "KernelConfigAspectInfo", "kernel_config_aspect")

def _symlink_config(ctx, kernel_build, filename):
    """Symlinks the `.config` file of the `kernel_build` to a file with file name `{filename}`.

    The config file can later be compared with `data/kernel_config_option_test/{filename}`.

    Return:
        The file with name `{prefix}_config`, which points to the `.config` of the kernel.
    """
    kernel_config = kernel_build[KernelConfigAspectInfo].kernel_config
    config_file = utils.find_file(
        name = ".config",
        files = kernel_config.files.to_list(),
        what = "{}: kernel_config outputs".format(kernel_build.label),
    )

    # Create symlink so that the Python test script compares with the correct expected file.
    symlink = ctx.actions.declare_file("{}/{}".format(ctx.label.name, filename))
    ctx.actions.symlink(output = symlink, target_file = config_file)

    return symlink

def _get_config_attrs_common(transition):
    """Common attrs for getting `.config` of the given `kernel_build` with the given transition."""
    attrs = {
        "kernel_build": attr.label(cfg = transition, aspects = [kernel_config_aspect], mandatory = True),
    }
    if transition != None:
        attrs.update({
            "_allowlist_function_transition": attr.label(
                default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
            ),
        })
    return attrs

def _get_transitioned_config_impl(ctx):
    """Common impl for getting `.config` of the given `kernel_build` with the given transition."""
    files = [
        _symlink_config(ctx, kernel_build, key + "_config")
        for key, kernel_build in ctx.split_attr.kernel_build.items()
    ]
    return DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files))

def _transition_test(name, test_data_rule, expected):
    """Test the effect of a flag on `kernel_config`.

    Args:
        name: name of test
        test_data_rule: `rule()` to get the actual `.config` of a kernel.
        expected: A list of expected files.
    """
    kernel_build(
        name = name + "_kernel",
        srcs = ["//common:kernel_aarch64_sources"],
        outs = [],
        build_config = "//common:build.config.gki.aarch64",
        tags = ["manual"],
    )
    test_data_rule(
        name = name + "_actual",
        kernel_build = name + "_kernel",
    )
    native.filegroup(
        name = name + "_expected",
        srcs = expected,
    )
    contain_lines_test(
        name = name,
        expected = name + "_expected",
        actual = name + "_actual",
    )

_lto_test_data = rule(
    implementation = _get_transitioned_config_impl,
    doc = "Get `.config` for a kernel with the LTO transition.",
    attrs = _get_config_attrs_common(lto_transition),
)

def _lto_test(name):
    """Test the effect of a `--lto` on `kernel_config`."""
    _transition_test(
        name = name,
        test_data_rule = _lto_test_data,
        expected = ["data/kernel_config_option_test/{}_config".format(lto) for lto in LTO_VALUES],
    )

_kasan_test_data = rule(
    implementation = _get_transitioned_config_impl,
    doc = "Get `.config` for a kernel with the kasan transition.",
    attrs = _get_config_attrs_common(kasan_transition),
)

def _get_config_impl(ctx):
    symlink = _symlink_config(ctx, ctx.attr.kernel_build, ctx.attr.prefix + "_config")
    return DefaultInfo(files = depset([symlink]), runfiles = ctx.runfiles(files = [symlink]))

_get_config = rule(
    implementation = _get_config_impl,
    doc = "Get `.config` for a kernel.",
    attrs = dicts.add(_get_config_attrs_common(None), {
        "prefix": attr.string(doc = "prefix of output file name"),
    }),
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
        # FIXME reuse _transition_test here.
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
        # FIXME
        #        partial.make(
        #            _transition_test,
        #            test_data_rule = _kasan_test_data,
        #            expected = ["data/kernel_config_option_test/{}kasan_config".format(kasan) for kasan in ("", "no")],
        #        ),
        _trim_test,
        _combined_option_test,
    )
