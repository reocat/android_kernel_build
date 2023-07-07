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

"""Selects defconfig fragments based on flag and attribute."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _defconfig_fragment_string_flag_selector_impl(ctx):
    flag_value = ctx.attr.flag[BuildSettingInfo].value
    flag_value = ctx.attr.transforms.get(flag_value) or flag_value

    files_depsets = []

    for target, expected_value in ctx.attr.files.items():
        if expected_value == flag_value:
            files_depsets.append(target.files)

    return DefaultInfo(files = depset(transitive = files_depsets))

defconfig_fragment_string_flag_selector = rule(
    implementation = _defconfig_fragment_string_flag_selector_impl,
    doc = """Selects defconfig fragments based on flag and attribute.""",
    attrs = {
        "flag": attr.label(
            doc = "`string_flag` / `string_setting`",
            mandatory = True,
            providers = [BuildSettingInfo],
        ),
        "files": attr.label_keyed_string_dict(
            doc = "key: label to files. value: value of flag.",
            allow_files = True,
        ),
        "transforms": attr.string_dict(
            doc = "Apply these transforms on `flag`'s value before using",
        ),
    },
)

def _defconfig_fragment_bool_flag_selector_impl(ctx):
    flag_value = ctx.attr.flag[BuildSettingInfo].value
    if not flag_value:
        flag_value = ctx.attr.attr_val

    if flag_value:
        files_depsets = [target.files for target in ctx.attr.true_files]
    else:
        files_depsets = [target.files for target in ctx.attr.false_files]

    return DefaultInfo(files = depset(transitive = files_depsets))

defconfig_fragment_bool_flag_selector = rule(
    implementation = _defconfig_fragment_bool_flag_selector_impl,
    doc = """Selects defconfig fragments based on flag and attribute.

Value is determined in the following order:

- If flag is set to true, use true
- Otherwise if attribute is set to true, use true
- Otherwise use false
""",
    attrs = {
        "flag": attr.label(
            doc = "`bool_flag` / `bool_setting`",
            mandatory = True,
            providers = [BuildSettingInfo],
        ),
        "true_files": attr.label_list(
            doc = "files when the flag is set to true",
            allow_files = True,
        ),
        "false_files": attr.label_list(
            doc = "files when the flag is set to false",
            allow_files = True,
        ),
        "attr_val": attr.bool(
            doc = "default value of attribute. This is used when the flag is unset.",
        ),
    },
)
