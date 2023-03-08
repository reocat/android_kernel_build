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

"""Helper for `kernel_env` to get toolchains for different platforms."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "CPP_TOOLCHAIN_TYPE", "find_cpp_toolchain", "use_cpp_toolchain")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "C_COMPILE_ACTION_NAME")  # or our fake rules_cc
load(":common_providers.bzl", "KernelEnvToolchainInfo")

def _kernel_env_toolchain_helper_transition_impl(_settings, attr):
    if not attr.platform:
        return None

    return {
        "//command_line_option:platforms": attr.platform,
    }

_kernel_env_toolchain_helper_transition = transition(
    implementation = _kernel_env_toolchain_helper_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _kernel_env_toolchain_helper_impl(ctx):
    if not ctx.attr._config_is_hermetic_cc[BuildSettingInfo].value:
        return []

    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = [],  #copts
    )
    compile_command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = C_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )

    return KernelEnvToolchainInfo(
        toolchain_id = cc_toolchain.toolchain_id,
        all_files = cc_toolchain.all_files,
        cflags = compile_command_line,
    )

kernel_env_toolchain_helper = rule(
    doc = """Helper for `kernel_env` to get toolchains for different platforms.""",
    implementation = _kernel_env_toolchain_helper_impl,
    attrs = {
        "platform": attr.label(doc = """The platform to resolve toolchain against.

            If empty, use `"//command_line_option:platforms"` configured on the target.
            """),
        "_config_is_hermetic_cc": attr.label(default = "//build/kernel/kleaf:config_hermetic_cc"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = use_cpp_toolchain(mandatory = True),
    fragments = ["cpp"],
    cfg = _kernel_env_toolchain_helper_transition,
)
