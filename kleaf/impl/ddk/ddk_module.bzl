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

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
)
load(":kernel_module.bzl", "kernel_module")
load(":ddk/ddk_module_info.bzl", "DdkModuleInfo")
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo", "ddk_headers")
load(":ddk/makefiles.bzl", "makefiles")

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
        srcs: sources.

            By default, this is `[{name}.c] + glob(["**/*.h"])`.
        hdrs: headers
        deps: Other [`kernel_module`](#kernel_module) or [`ddk_package`](#ddk_package)
        kernel_build: [`kernel_build`](#kernel_build)
        kwargs: Additional attributes to the internal rule.
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if srcs == None:
        srcs = [
            "{}.c".format(name),
        ] + native.glob(
            ["**/*.h"],
        )

    out = "{}.ko".format(name)

    kernel_module(
        name = name,
        kernel_build = kernel_build,
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_module_symvers_name = "{name}_Module.symvers".format(name = name),
        internal_drop_modules_order = True,
        srcs = srcs,
        hdrs = hdrs,
        kernel_module_deps = deps,
        outs = [out],
        **kwargs
    )

    makefile_kwargs = dict(kwargs)
    makefile_kwargs["visibility"] = ["//visibility:private"]
    makefiles(
        name = name + "_makefiles",
        module_srcs = srcs,
        module_hdrs = hdrs,
        module_out = out,
        module_deps = deps,
        **makefile_kwargs
    )
