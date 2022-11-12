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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:utils.bzl", "kernel_utils")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//build/kernel/kleaf/tests:test_utils.bzl", "test_utils")

def _check_auto_module_outs_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    main_action = test_utils.find_action(env, "KernelBuild" + kernel_utils.local_mnemonic_suffix(ctx))
    script = test_utils.get_shell_script(env, main_action)

    asserts.true(
        env,
        "lib/modules/*/kernel -name '*.ko' -exec cp -t" in script,
        "should copy all ko files",
    )

    asserts.equals(
        env,
        ctx.attr.expect_unstripped_modules,
        "${OUT_DIR} -name '*.ko' -exec cp -t" in script,
        "should {}grab unstripped modules".format(
            "" if ctx.attr.expect_unstripped_modules else "not ",
        ),
    )

    asserts.false(
        env,
        "remaining_ko_files" in script,
        "should not check remaining ko files",
    )

    expected_dir_name = target_under_test.label.name + "_" + ctx.attr.attr_under_test
    modules_dir = test_utils.find_output(main_action, expected_dir_name)
    asserts.true(env, modules_dir, "Can't find {} in outputs".format(expected_dir_name))
    asserts.true(env, modules_dir.is_directory, "{} is not directory".format(expected_dir_name))

    asserts.false(
        env,
        hasattr(target_under_test[OutputGroupInfo], "_auto_key"),
    )

    return analysistest.end(env)

_check_auto_module_outs_test = analysistest.make(
    impl = _check_auto_module_outs_test_impl,
    attrs = {
        "_config_is_local": attr.label(
            default = "//build/kernel/kleaf:config_local",
        ),
        "expect_unstripped_modules": attr.bool(),
        "attr_under_test": attr.string(),
    },
)

def _good_test(name, attr_under_test, **kwargs):
    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = [],
        tags = ["manual"],
        **kwargs
    )

    _check_auto_module_outs_test(
        name = name,
        target_under_test = name + "_kernel_build",
        expect_unstripped_modules = kwargs.get("collect_unstripped_modules"),
        attr_under_test = attr_under_test,
    )

def _bad_test(name, **kwargs):
    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = [],
        tags = ["manual"],
        **kwargs
    )
    failure_test(
        name = name,
        target_under_test = name + "_kernel_build",
        error_message_substrs = ['must be a list of in-tree drivers or a single item "auto"'],
    )

def kernel_build_auto_module_outs_test(name):
    tests = []

    for attr in ("module_outs", "module_implicit_outs"):
        for collect_unstripped_modules in (True, False):
            unstripped_text = "" if collect_unstripped_modules else "out"

            test_name = "{}_with{}_unstripped_{}".format(name, unstripped_text, attr)

            _good_test(
                name = test_name + "_has_auto",
                attr_under_test = attr,
                collect_unstripped_modules = collect_unstripped_modules,
                **{attr: ["auto"]}
            )
            tests.append(test_name + "_has_auto")

            _bad_test(
                name = test_name + "_not_just_auto",
                collect_unstripped_modules = collect_unstripped_modules,
                **{attr: ["auto", "foo.ko"]}
            )
            tests.append(test_name + "_not_just_auto")

    native.test_suite(
        name = name,
        tests = tests,
    )
