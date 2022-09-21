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

# Test `strip_modules`.

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")

# Check effect of strip_modules
def _strip_modules_test_impl(ctx):
    env = analysistest.begin(ctx)
    found_action = False
    for action in analysistest.target_actions(env):
        if action.mnemonic == "KernelBuild":
            for arg in action.argv:
                if "INSTALL_MOD_STRIP=1" in arg:
                    found_action = True
                    break
    asserts.equals(
        env,
        actual = found_action,
        expected = ctx.attr.expect_strip_modules,
        msg = "expect_strip_modules = {}, but INSTALL_MOD_STRIP=1 {}".format(ctx.attr.expect_strip_modules, "found" if found_action else "not found"),
    )
    return analysistest.end(env)

_strip_modules_test = analysistest.make(
    impl = _strip_modules_test_impl,
    attrs = {
        "expect_strip_modules": attr.bool(),
    },
)

def kernel_build_strip_modules_test(name):
    """Define tests for `strip_modules`.

    Args:
      name: Name of this test suite.
    """
    tests = []

    for strip_modules in (True, False):
        strip_modules_str = str(strip_modules)
        kernel_build(
            name = name + "_" + strip_modules_str + "_subject",
            tags = ["manual"],
            build_config = "//common:build.config.gki.aarch64",
            outs = [],
            strip_modules = strip_modules,
        )
        _strip_modules_test(
            name = name + "_strip_modules_" + strip_modules_str,
            target_under_test = name + "_" + strip_modules_str + "_subject",
            expect_strip_modules = strip_modules,
        )
        tests.append(name + "_strip_modules_" + strip_modules_str)

    native.test_suite(
        name = name,
        tests = tests,
    )
