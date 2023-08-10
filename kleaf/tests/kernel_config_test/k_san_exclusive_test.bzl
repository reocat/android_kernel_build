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

"""Tests that --kasan and --kasan_sw_tags cannot be set simultaneously."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")

def _k_san_exclusive_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "cannot have both --kasan and --kasan_sw_tags simultaneously")
    return analysistest.end(env)

_k_san_exclusive_test = analysistest.make(
    impl = _k_san_exclusive_test_impl,
    config_settings = {
        str(Label("//build/kernel/kleaf:kasan")): True,
        str(Label("//build/kernel/kleaf:kasan_sw_tags")): True,
    },
    expect_failure = True,
)

def k_san_exclusive_test(name):
    """Tests that --kasan and --kasan_sw_tags cannot be set simultaneously.

    Args:
        name: name of the test
    """
    kernel_build(
        name = name + "_subject",
        tags = ["manual"],
        build_config = Label("//common:build.config.gki.aarch64"),
        outs = [],
    )
    _k_san_exclusive_test(
        name = name,
        target_under_test = name + "_subject",
    )
