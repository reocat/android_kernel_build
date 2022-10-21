# Copyright (C) 2021 The Android Open Source Project
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

# All public rules and macros to build the kernel.
# This file serves as a central place for users to import these public
# rules and macros. The implementations stays in sub-extensions,
# which is not expected to be loaded directly by users.

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/kernel/kleaf/impl:abi/kernel_build_abi.bzl", _kernel_build_abi = "kernel_build_abi")
load("//build/kernel/kleaf/impl:abi/kernel_build_abi_dist.bzl", _kernel_build_abi_dist = "kernel_build_abi_dist")
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", _ddk_headers = "ddk_headers")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", _ddk_module = "ddk_module")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", _kernel_images = "kernel_images")
load("//build/kernel/kleaf/impl:kernel_build.bzl", _kernel_build_macro = "kernel_build")
load("//build/kernel/kleaf/impl:kernel_build_config.bzl", _kernel_build_config = "kernel_build_config")
load("//build/kernel/kleaf/impl:kernel_compile_commands.bzl", _kernel_compile_commands = "kernel_compile_commands")
load("//build/kernel/kleaf/impl:kernel_dtstree.bzl", "DtstreeInfo", _kernel_dtstree = "kernel_dtstree")
load("//build/kernel/kleaf/impl:kernel_filegroup.bzl", _kernel_filegroup = "kernel_filegroup")
load("//build/kernel/kleaf/impl:kernel_kythe.bzl", _kernel_kythe = "kernel_kythe")
load("//build/kernel/kleaf/impl:kernel_module.bzl", _kernel_module_macro = "kernel_module")
load("//build/kernel/kleaf/impl:kernel_modules_install.bzl", _kernel_modules_install = "kernel_modules_install")
load("//build/kernel/kleaf/impl:kernel_unstripped_modules_archive.bzl", _kernel_unstripped_modules_archive = "kernel_unstripped_modules_archive")
load("//build/kernel/kleaf/impl:merged_kernel_uapi_headers.bzl", _merged_kernel_uapi_headers = "merged_kernel_uapi_headers")

# Re-exports. This is the list of public rules and macros.
ddk_headers = _ddk_headers
ddk_module = _ddk_module
kernel_build = _kernel_build_macro
kernel_build_abi = _kernel_build_abi
kernel_build_abi_dist = _kernel_build_abi_dist
kernel_build_config = _kernel_build_config
kernel_compile_commands = _kernel_compile_commands
kernel_dtstree = _kernel_dtstree
kernel_filegroup = _kernel_filegroup
kernel_images = _kernel_images
kernel_kythe = _kernel_kythe
kernel_module = _kernel_module_macro
kernel_modules_install = _kernel_modules_install
kernel_unstripped_modules_archive = _kernel_unstripped_modules_archive
merged_kernel_uapi_headers = _merged_kernel_uapi_headers

MyRuleInfo = provider(
    fields = {
        "build_config": "",
        "arch": "",
    },
)

def _impl(ctx):
    print("{}: build_config {}".format(ctx.attr.name, ctx.file.build_config))
    print("{}: arch {}".format(ctx.attr.name, ctx.attr._real_arch[BuildSettingInfo].value))

    return MyRuleInfo(
        build_config = ctx.file.build_config,
        arch = ctx.attr._real_arch[BuildSettingInfo].value,
    )

myrule = rule(
    implementation = _impl,
    attrs = {
        "build_config": attr.label(allow_single_file = True),
        "_real_arch": attr.label(default = "//build/kernel/kleaf:my_cpu"),
    },
)

def _trans_impl(settings, attr):
    return {
        "//build/kernel/kleaf:my_cpu": attr.arch,
    }

myrule_transition = transition(
    implementation = _trans_impl,
    inputs = [],
    outputs = ["//build/kernel/kleaf:my_cpu"],
)

def _alias_impl(ctx):
    return [ctx.attr.actual[MyRuleInfo]]

my_alias = rule(
    implementation = _alias_impl,
    attrs = {
        "arch": attr.string(),
        "actual": attr.label(providers = [MyRuleInfo]),
        "_allowlist_function_transition": attr.label(
            # Because we don't know where the common package is
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = myrule_transition,
)
