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
load(
    ":common_providers.bzl",
    "KernelEnvToolchainInfo",
    "KernelResolvedToolchainInfo",
)

def _sanitize_flag(flag):
    """Turns paths into ones relative to $PWD for each flag.

    Kbuild executes the compiler in subdirectories, hence an absolute path is needed."""

    if flag.startswith("--sysroot"):
        key, value = flag.split("=", 2)
        if not value.startswith("/"):
            value = "$PWD/" + value
        return "{}={}".format(key, value)

    return flag

def _kernel_multi_toolchain_impl(ctx):
    env = {}
    if not ctx.attr._config_is_hermetic_cc[BuildSettingInfo].value:
        return KernelEnvToolchainInfo(env = env, all_files = depset())

    exec = ctx.attr._exec_toolchain[KernelResolvedToolchainInfo]
    target = ctx.attr._target_toolchain[KernelResolvedToolchainInfo]

    env["HOSTCFLAGS"] = " ".join([_sanitize_flag(flag) for flag in exec.cflags])
    env["USERCFLAGS"] = " ".join([_sanitize_flag(flag) for flag in target.cflags])

    all_files = depset(transitive = [exec.all_files, target.all_files])

    return KernelEnvToolchainInfo(
        env = env,
        # FIXME respect toolchain_version
        all_files = all_files,
    )

kernel_multi_toolchain = rule(
    doc = """Helper for `kernel_env` to get toolchains for different platforms.""",
    implementation = _kernel_multi_toolchain_impl,
    attrs = {
        "_exec_toolchain": attr.label(
            default = "//build/kernel/kleaf/impl:kernel_toolchain",
            cfg = "exec",
            providers = [KernelResolvedToolchainInfo],
        ),
        "_target_toolchain": attr.label(
            default = "//build/kernel/kleaf/impl:kernel_toolchain",
            providers = [KernelResolvedToolchainInfo],
        ),
        "_config_is_hermetic_cc": attr.label(default = "//build/kernel/kleaf:config_hermetic_cc"),
    },
)
