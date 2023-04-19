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

def _kernel_toolchains_impl(ctx):
    # FIXME what about toolchain_version.startswith("//build/kernel/kleaf/tests/")
    exec = ctx.attr.exec_toolchain[KernelResolvedToolchainInfo]
    target = ctx.attr.target_toolchain[KernelResolvedToolchainInfo]
    all_files = depset(transitive = [exec.all_files, target.all_files])

    env = {}

    return KernelEnvToolchainInfo(
        env = env,
        all_files = all_files,
        exec_compiler_version = exec.compiler_version,
        target_compiler_version = target.compiler_version,
    )

kernel_toolchains = rule(
    doc = """Helper for `kernel_env` to get toolchains for different platforms.""",
    implementation = _kernel_toolchains_impl,
    attrs = {
        "exec_toolchain": attr.label(
            cfg = "exec",
            providers = [KernelResolvedToolchainInfo],
        ),
        "target_toolchain": attr.label(
            providers = [KernelResolvedToolchainInfo],
        ),
    },
)
