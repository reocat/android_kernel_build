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

"""Returns kmi symbols checks for a `kernel_build`."""

load(
    ":common_providers.bzl",
    "KernelBuildAbiInfo",
)

def _get_kmi_symbol_checks_impl(ctx):
    kmi_strict_mode_out = ctx.attr.kernel_build[KernelBuildAbiInfo].kmi_strict_mode_out
    kmi_strict_mode_out = depset([kmi_strict_mode_out]) if kmi_strict_mode_out else None
    return DefaultInfo(files = kmi_strict_mode_out)

get_kmi_symbol_checks = rule(
    doc = "Returns kmi symbol checks for a `kernel_build`.",
    implementation = _get_kmi_symbol_checks_impl,
    attrs = {
        "kernel_build": attr.label(providers = [KernelBuildAbiInfo]),
    },
)
