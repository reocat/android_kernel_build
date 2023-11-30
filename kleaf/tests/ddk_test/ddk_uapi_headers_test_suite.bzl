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
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:ddk/ddk_uapi_headers.bzl", "ddk_uapi_headers")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")

def check_ddk_uapi_headers_info(ctx, env):
    """Check that the target implements."""
    analysistest.target_under_test(env)

def _good_uapi_headers_test_impl(ctx):
    env = analysistest.begin(ctx)
    check_ddk_uapi_headers_info(ctx, env)
    return analysistest.end(env)

_good_uapi_headers_test = analysistest.make(
    impl = _good_uapi_headers_test_impl,
)

def _ddk_uapi_headers_good_headers_test(
        name,
        srcs = None):
    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = ["vmlinux"],
        tags = ["manual"],
    )

    ddk_uapi_headers(
        name = name + "_headers",
        srcs = srcs,
        out = "good_headers.tar.gz",
        kernel_build = name + "_kernel_build",
    )

    _good_uapi_headers_test(
        name = name,
        target_under_test = name + "_headers",
    )

def _ddk_uapi_headers_bad_headers_test(name, srcs, error_message):
    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = ["vmlinux"],
        tags = ["manual"],
    )

    ddk_uapi_headers(
        name = name + "_headers",
        srcs = srcs,
        out = "bad_headers.tar.gz",
        kernel_build = name + "_kernel_build",
    )

    failure_test(
        name = name,
        target_under_test = name + "_headers",
    )

def ddk_uapi_headers_test_suite(name):
    """Defines analysis test for `ddk_uapi_headers`."""

    tests = []

    _ddk_uapi_headers_good_headers_test(
        name = name + "_good_header",
        srcs = ["include/uapi/uapi.h"],
    )
    tests.append(name + "_self")

    _ddk_uapi_headers_bad_headers_test(
        name = name + "_bad_header",
        srcs = ["include/uapi/uapi_nonexistent.h"],
        error_message = "compile",
    )
    tests.append(name + "_bad_header")

    native.test_suite(
        name = name,
        tests = tests,
    )
