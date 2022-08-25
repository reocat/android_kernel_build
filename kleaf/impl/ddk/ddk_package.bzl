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

load(":kernel_module.bzl", "SIBLING_NAMES", "check_kernel_build")
load(
    "//build/kernel/kleaf/artifact_tests:kernel_test.bzl",
    "kernel_module_test",
)

def ddk_package(
        name,
        kernel_build,
        deps = None,
        **kwargs):
    """
    Executes post actions for [`ddk_module`](#ddk_module)s in the same package.

    This includes `make modules_install`, etc.

    This functions similar to a non-DDK external [`kernel_module`](#kernel_module).

    Args:
        deps: A list of [`ddk_module`](#ddk_module) defined in the same package.
    """

    _ddk_package(
        name = name,
        deps = deps,
        kernel_build = kernel_build,
        **kwargs
    )

    kernel_module_test(
        name = name + "_test",
        modules = [name],
        **kwargs
    )

    for sibling_name in SIBLING_NAMES:
        sibling_kwargs = dict(kwargs)
        sibling_kwargs["tags"] = (sibling_kwargs.get("tags") or []) + ["manual"]
        _ddk_package(
            name = name + "_" + sibling_name,
            deps = [dep + "_" + sibling_name for dep in (deps or [])],
            kernel_build = kernel_build,
            **sibling_kwargs
        )

def _ddk_package_impl(ctx):
    check_kernel_build(ctx.attr.deps, ctx.attr.kernel_build, ctx.label)

    inputs = []
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_srcs

    command = ctx.attr.kernel_build[KernelEnvInfo].setup
    command += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_setup

    command += """
             # Restore output kernel modules

    """

_ddk_package = rule(
    implementation = _ddk_package_impl,
    attrs = {
        "deps": attr.label_list(),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildExtModuleInfo],
        ),
    },
)
