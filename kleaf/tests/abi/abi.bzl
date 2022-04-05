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

# Unit tests on rules

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//build/kernel/kleaf:kernel.bzl",
    "testing",
)

def _abi_diff_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    asserts.true(env, target_under_test[DefaultInfo].files.to_list())
    return analysistest.end(env)

abi_diff_test = analysistest.make(_abi_diff_test_impl)

def _abi_diff_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "This rule should never work")
    return analysistest.end(env)

abi_diff_failure_test = analysistest.make(_abi_diff_failure_test_impl, expect_failure = True)

def abi_diff_and_test(name, expect_failure = None, **kwargs):
    testing.kernel_abi_diff(
        name = name,
        tags = ["manual"],
        **kwargs
    )
    if expect_failure:
        abi_diff_failure_test(
            name = name + "_test",
            target_under_test = name,
        )
    else:
        abi_diff_test(
            name = name + "_test",
            target_under_test = name,
        )

def abi_diff_test_suite(name):
    abi_diff_and_test(
        name = name + "_exact",
        baseline = "data/baseline.xml",
        new = "data/baseline.xml",
        kmi_enforced = True,
    )
    abi_diff_and_test(
        name = name + "_equivalent",
        baseline = "data/new.xml",
        new = "data/new2.xml",
        kmi_enforced = True,
    )
    abi_diff_and_test(
        name = name + "_added_enforced",
        expect_failure = True,
        baseline = "data/baseline.xml",
        new = "data/new.xml",
        kmi_enforced = True,
    )

    native.test_suite(
        name = name,
        tests = [
            name + "_exact_test",
            name + "_equivalent_test",
            name + "_added_enforced_test",
        ],
    )
