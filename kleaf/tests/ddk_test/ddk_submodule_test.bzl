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

load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", "ddk_headers")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", "ddk_module")
load("//build/kernel/kleaf/impl:ddk/ddk_submodule.bzl", "ddk_submodule")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load(":ddk_module_test.bzl", "ddk_module_test")

def _ddk_module_test_make(
        name,
        expected_inputs = None,
        expected_hdrs = None,
        expected_includes = None,
        **kwargs):
    ddk_module(
        name = name + "_module",
        tags = ["manual"],
        **kwargs
    )

    ddk_module_test(
        name = name,
        target_under_test = name + "_module",
        expected_inputs = expected_inputs,
        expected_hdrs = expected_hdrs,
        expected_includes = expected_includes,
    )

def ddk_submodule_test(name):
    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = [],
        tags = ["manual"],
    )

    ddk_headers(
        name = name + "_headers",
        includes = ["include"],
        hdrs = ["include/subdir.h"],
        tags = ["manual"],
    )

    tests = []

    # Simple test

    ddk_submodule(
        name = name + "_good_submodule",
        out = name + "_good_submodule.ko",
        srcs = ["dep.c", "self.h"],
    )

    _ddk_module_test_make(
        name = name + "_good",
        kernel_build = name + "_kernel_build",
        deps = [name + "_good_submodule"],
        expected_inputs = ["dep.c", "self.h"],
    )
    tests.append(name + "_good")

    # Test on locally depending on a ddk_headers target

    ddk_submodule(
        name = name + "_external_headers_submodule",
        out = name + "_external_headers_submodule.ko",
        deps = [name + "_headers"],
        srcs = [],
    )

    _ddk_module_test_make(
        name = name + "_external_headers",
        kernel_build = name + "_kernel_build",
        deps = [name + "_external_headers_submodule"],
        expected_inputs = ["include/subdir.h"],
    )
    tests.append(name + "_external_headers")

    # Test on exporting a ddk_headers target

    ddk_submodule(
        name = name + "_export_ddk_headers_submodule",
        out = name + "_export_ddk_headers_submodule.ko",
        hdrs = [name + "_headers"],
        srcs = [],
    )

    _ddk_module_test_make(
        name = name + "_export_ddk_headers",
        kernel_build = name + "_kernel_build",
        deps = [name + "_export_ddk_headers_submodule"],
        expected_inputs = ["include/subdir.h"],
        expected_hdrs = ["include/subdir.h"],
        expected_includes = [native.package_name() + "/include"],
    )
    tests.append(name + "_export_ddk_headers")

    # Test on exporting headers + includes
    ddk_submodule(
        name = name + "_export_my_headers_submodule",
        out = name + "_export_my_headers_submodule.ko",
        hdrs = ["include/subdir.h"],
        includes = ["include"],
        srcs = [],
    )

    _ddk_module_test_make(
        name = name + "_export_my_headers",
        kernel_build = name + "_kernel_build",
        deps = [name + "_export_my_headers_submodule"],
        expected_inputs = ["include/subdir.h"],
        expected_hdrs = ["include/subdir.h"],
        expected_includes = [native.package_name() + "/include"],
    )
    tests.append(name + "_export_my_headers")

    native.test_suite(
        name = name,
        tests = tests,
    )
