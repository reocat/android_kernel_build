# Copyright (C) 2023 The Android Open Source Project
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

"""Tests `trim_nonlisted_kmi` and `force_disable_trim`."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load(
    "//build/kernel/kleaf/impl:abi/trim_nonlisted_kmi_utils.bzl",
    "FORCE_DISABLE_TRIM",
)

# Implementation notes: A better test would be to examine the configurations
# of every single ConfiguredTarget that _kernel_build / kernel_config
# etc. directly depends on, and check that
# //build/kernel/kleaf/impl:trim_nonlisted_kmi_setting is set to unknown.
# For example, the _kernel_build below should depend on build.config.* that
# are configured with //build/kernel/kleaf/impl:trim_nonlisted_kmi_setting
# set to unknown.
#
# However, we don't have a way to access flag values unless the target declares
# the flag as an attribute. Hence, we only check kernel_config / kernel_env
# etc. here.

TrimAspectInfo = provider(
    "Provides the value of `trim_nonlisted_kmi_setting`.",
    fields = {
        "label": "Label of this target",
        "value": "The tristate value of `trim_nonlisted_kmi_setting` of this target",
        "base_info": "The `TrimAspectInfo` of the `base_kernel`",
        "config_info": "The `TrimAspectInfo` of `kernel_config`",
        "modules_prepare_info": "The `TrimAspectInfo` of `kernel_modules_prepare`",
        "env_info": "The `TrimAspectInfo` of `kernel_env`",
    },
)

def _trim_aspect_impl(_target, ctx):
    if ctx.rule.kind == "_kernel_build":
        base_kernel = ctx.rule.attr.base_kernel
        base_info = base_kernel[TrimAspectInfo] if base_kernel else None

        return TrimAspectInfo(
            label = ctx.label,
            value = ctx.rule.attr.trim_nonlisted_kmi,
            config_info = ctx.rule.attr.config[TrimAspectInfo],
            modules_prepare_info = ctx.rule.attr.modules_prepare[TrimAspectInfo],
            base_info = base_info,
        )
    elif ctx.rule.kind == "kernel_config":
        return TrimAspectInfo(
            label = ctx.label,
            value = ctx.rule.attr.trim_nonlisted_kmi,
            env_info = ctx.rule.attr.env[TrimAspectInfo],
        )
    elif ctx.rule.kind == "kernel_env":
        return TrimAspectInfo(
            label = ctx.label,
            value = ctx.rule.attr.trim_nonlisted_kmi,
        )
    elif ctx.rule.kind == "modules_prepare":
        return TrimAspectInfo(
            label = ctx.label,
            config_info = ctx.rule.attr.config[TrimAspectInfo],
            value = ctx.rule.attr.trim_nonlisted_kmi,
        )

    fail("{label}: Unable to get `_trim_nonlisted_kmi_setting` because {kind} is not supported.".format(
        kind = ctx.rule.kind,
        label = ctx.label,
    ))

_trim_aspect = aspect(
    implementation = _trim_aspect_impl,
    doc = "An aspect describing the `trim_nonlisted_kmi_setting` of a `_kernel_build`",
    attr_aspects = [
        "base_kernel",
        "config",
        "env",
        "modules_prepare",
    ],
)

def _check_kernel_config_trim_attr(env, expect_trim, config_info):
    """Check trim_nonlisted_kmi_setting of all internal targets of kernel_build."""
    asserts.equals(
        env,
        expect_trim,
        config_info.value,
        config_info.label,
    )
    asserts.equals(
        env,
        expect_trim,
        config_info.env_info.value,
        config_info.env_info.label,
    )

def _check_kernel_build_trim_attr(env, expect_trim, target_trim_info):
    """Check trim_nonlisted_kmi_setting of all internal targets of kernel_build."""
    asserts.equals(
        env,
        expect_trim,
        target_trim_info.value,
        target_trim_info.label,
    )
    asserts.equals(
        env,
        expect_trim,
        target_trim_info.modules_prepare_info.value,
        target_trim_info.modules_prepare_info.label,
    )
    _check_kernel_config_trim_attr(env, expect_trim, target_trim_info.config_info)
    _check_kernel_config_trim_attr(env, expect_trim, target_trim_info.modules_prepare_info.config_info)

def _trim_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    if target_under_test[TrimAspectInfo].base_info == None:
        asserts.false(
            env,
            ctx.attr.has_base,
            target_under_test.label,
        )
    else:
        _check_kernel_build_trim_attr(
            env,
            ctx.attr.base_expect_trim,
            target_under_test[TrimAspectInfo].base_info,
        )
    _check_kernel_build_trim_attr(
        env,
        ctx.attr.expect_trim,
        target_under_test[TrimAspectInfo],
    )

    return analysistest.end(env)

_trim_analysis_test = analysistest.make(
    impl = _trim_analysis_test_impl,
    attrs = {
        "has_base": attr.bool(mandatory = True),
        "base_expect_trim": attr.bool(),
        "expect_trim": attr.bool(mandatory = True),
    },
    extra_target_under_test_aspects = [
        _trim_aspect,
    ],
)

def trim_test(name):
    """Tests the effect of `trim_nonlisted_kmi` on dependencies.

    Args:
        name: name of the test suite.
    """

    for base_trim in (True, False):
        base_trim_str = "trim" if base_trim else "notrim"
        kernel_build(
            name = name + "_{}_base_build".format(base_trim_str),
            build_config = "build.config.kernel",
            outs = [],
            trim_nonlisted_kmi = base_trim,
            kmi_symbol_list = "symbol_list_base",
            tags = ["manual"],
        )

        _trim_analysis_test(
            name = name + "_{}_base_test".format(base_trim_str),
            target_under_test = name + "_{}_base_build".format(base_trim_str),
            # {name}_{base_trim_str}_base_build doens't have a base_kernel
            has_base = False,
            expect_trim = base_trim,
        )

        for device_trim in (True, False):
            device_trim_str = "trim" if device_trim else "notrim"

            kernel_build(
                name = name + "_{}_{}_device_build".format(base_trim_str, device_trim_str),
                build_config = "build.config.device",
                base_kernel = name + "_{}_base_build".format(base_trim_str),
                outs = [],
                trim_nonlisted_kmi = device_trim,
                kmi_symbol_list = "symbol_list_device",
                tags = ["manual"],
            )

            _trim_analysis_test(
                name = name + "_{}_{}_device_test".format(base_trim_str, device_trim_str),
                target_under_test = name + "_{}_{}_device_build".format(base_trim_str, device_trim_str),
                has_base = True,
                base_expect_trim = base_trim,
                expect_trim = device_trim,
            )

    native.test_suite(
        name = name,
        # tests = all tests
    )
