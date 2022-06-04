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

load(":ddk/ddk_module_info.bzl", "DdkModuleInfo")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
)

def ddk_module(
        name,
        kernel_build,
        srcs = None,
        hdrs = None,
        deps = None,
        **kwargs):
    """
    Defines a DDK (Driver Development Kit) module.

    Args:
        name: Name of target. This should be name of the output `.ko` file without the suffix.
        srcs: sources
        hdrs: headers
        deps: Other [`kernel_module`](#kernel_module) or [`ddk_package`](#ddk_package)
        kernel_build: [`kernel_build`](#kernel_build)
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if srcs == None:
        srcs = [
            "{}.c".format(name),
        ]

    _ddk_module(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        kernel_build = kernel_build,
        deps = deps,
        **kwargs
    )

def _ddk_module_impl(ctx):
    return DdkModuleInfo(
        srcs = ctx.attr.srcs,
        hdrs = ctx.attr.hdrs,
        deps = ctx.attr.deps,
        kernel_build = ctx.attr.kernel_build,
    )

_ddk_module = rule(
    implementation = _ddk_module_impl,
    doc = """
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "hdrs": attr.label_list(
            allow_files = True,
        ),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildExtModuleInfo],
        ),
        "deps": attr.label_list(
            providers = [KernelEnvInfo, KernelModuleInfo],
        ),
    },
)
