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

def _prepend_pwd(value):
    if not value.startswith("/"):
        value = "$PWD/" + value
    return value

def _sanitize_flags(flags):
    """Turns paths into ones relative to $PWD for each flag.

    Kbuild executes the compiler in subdirectories, hence an absolute path is needed."""

    result_flags = []

    prev = None
    for index, flag in enumerate(flags):
        if prev in ("--sysroot", "-I", "-iquote", "-isystem"):
            result_flags.append(_prepend_pwd(flag))
        elif flag.startswith("--sysroot="):
            key, value = flag.split("=", 2)
            result_flags.append("{}={}".format(key, _prepend_pwd(value)))
        elif flag.startswith("-I"):
            key, value = flag[:2], flag[2:]
            result_flags.append("{}{}".format(key, _prepend_pwd(value)))
        else:
            result_flags.append(flag)
        prev = flag

    return result_flags

def _kernel_multi_toolchain_impl(ctx):
    if not ctx.attr._kernel_use_resolved_toolchains[BuildSettingInfo].value:
        return KernelEnvToolchainInfo(env = {}, all_files = depset())

    env = {}
    exec = ctx.attr.exec_toolchain[KernelResolvedToolchainInfo]
    target = ctx.attr.target_toolchain[KernelResolvedToolchainInfo]

    env["HOSTCFLAGS"] = " ".join(_sanitize_flags(exec.cflags))
    env["USERCFLAGS"] = " ".join(_sanitize_flags(target.cflags))

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
        "exec_toolchain": attr.label(
            cfg = "exec",
            providers = [KernelResolvedToolchainInfo],
        ),
        "target_toolchain": attr.label(
            providers = [KernelResolvedToolchainInfo],
        ),
        "_kernel_use_resolved_toolchains": attr.label(
            default = "//build/kernel/kleaf:experimental_kernel_use_resolved_toolchains",
        ),
    },
)
