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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load(
    "//build/kernel/kleaf/impl:abi/trim_nonlisted_kmi_utils.bzl",
    "TRIM_NONLISTED_KMI_SETTING_VALUES",
)

TrimAspectInfo = provider(
    "Provides the value of `trim_nonlisted_kmi_setting`.",
    fields = {
        "base_value": "The tristate value of `trim_nonlisted_kmi_setting` of the `base_kernel`",
        "value": "The tristate value of `trim_nonlisted_kmi_setting` of this target",
    },
)

def _trim_aspect_impl(target, ctx):
    if ctx.rule.kind == "_kernel_build":
        base_kernel = (ctx.rule.attr.base_kernel or [None])[0]
        base_value = base_kernel[TrimAspectInfo].value if base_kernel else TRIM_NONLISTED_KMI_SETTING_VALUES.unknown
        this_value = ctx.rule.attr._trim_nonlisted_kmi_setting[BuildSettingInfo].value

        return TrimAspectInfo(base_value = base_value, value = this_value)

    fail("{label}: Unable to get `_trim_nonlisted_kmi_setting` because {kind} is not supported.".format(
        kind = ctx.rule.kind,
        label = ctx.label,
    ))

_trim_aspect = aspect(
    implementation = _trim_aspect_impl,
    doc = "An aspect describing the `trim_nonlisted_kmi_setting` of a `_kernel_build`",
    attr_aspects = [
        "base_kernel",
    ],
)

def _trim_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    asserts.equals(
        env,
        ctx.attr.base_expect_trim,
        target_under_test[TrimAspectInfo].base_value,
        "For base",
    )
    asserts.equals(
        env,
        ctx.attr.expect_trim,
        target_under_test[TrimAspectInfo].value,
        "For value",
    )

    return analysistest.end(env)

_trim_analysis_test = analysistest.make(
    impl = _trim_analysis_test_impl,
    attrs = {
        "base_expect_trim": attr.string(),
        "expect_trim": attr.string(),
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
        base_trim_setting = TRIM_NONLISTED_KMI_SETTING_VALUES.enabled if base_trim else TRIM_NONLISTED_KMI_SETTING_VALUES.disabled
        kernel_build(
            name = name + "_{}_base_build".format(base_trim_setting),
            build_config = "build.config.kernel",
            outs = [],
            trim_nonlisted_kmi = base_trim,
            kmi_symbol_list = "symbol_list_base",
            tags = ["manual"],
        )

        _trim_analysis_test(
            name = name + "_{}_base_test".format(base_trim_setting),
            target_under_test = name + "_{}_base_build".format(base_trim_setting),
            # {name}_{base_trim_setting}_base_build doens't have a base_kernel
            base_expect_trim = TRIM_NONLISTED_KMI_SETTING_VALUES.unknown,
            expect_trim = base_trim_setting,
        )

        for device_trim in (True, False):
            device_trim_setting = TRIM_NONLISTED_KMI_SETTING_VALUES.enabled if device_trim else TRIM_NONLISTED_KMI_SETTING_VALUES.disabled

            kernel_build(
                name = name + "_{}_{}_device_build".format(base_trim_setting, device_trim_setting),
                build_config = "build.config.device",
                base_kernel = name + "_{}_base_build".format(base_trim_setting),
                outs = [],
                trim_nonlisted_kmi = device_trim,
                kmi_symbol_list = "symbol_list_device",
                tags = ["manual"],
            )

            _trim_analysis_test(
                name = name + "_{}_{}_device_test".format(base_trim_setting, device_trim_setting),
                target_under_test = name + "_{}_{}_device_build".format(base_trim_setting, device_trim_setting),
                base_expect_trim = base_trim_setting,
                expect_trim = device_trim_setting,
            )

    native.test_suite(
        name = name,
        # tests = all tests
    )
