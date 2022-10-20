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

"""
 Test Ramdisk Options.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", "kernel_images")
load("//build/kernel/kleaf:kernel.bzl", "kernel_build", "kernel_modules_install")

# Check effect of ramdisk_options
def _initramfs_test_impl(ctx):
    env = analysistest.begin(ctx)
    found_action = False
    for action in analysistest.target_actions(env):
        if action.mnemonic == ctx.attr.action_mnemonic:
            for arg in action.argv:
                if ctx.attr.expected_compress_args in arg:
                    found_action = True
                    break

    asserts.equals(
        env,
        actual = found_action,
        expected = True,
        msg = "expected_compress_args = {} not found.".format(
            ctx.attr.expected_compress_args,
        ),
    )
    return analysistest.end(env)

_initramfs_test = analysistest.make(
    impl = _initramfs_test_impl,
    attrs = {
        "action_mnemonic": attr.string(
            mandatory = True,
            values = [
                "Initramfs",
            ],
        ),
        "expected_compress_args": attr.string(),
        "expected_compress_ext": attr.string(),
    },
)

def initramfs_test(name):
    """Define tests for `ramdisk_options`.

    Args:
      name: Name of this test suite.
    """

    # Test setup
    kernel_build(
        name = name + "fallback_build",
        build_config = "build.config.fake,lz4",
        outs = [
            # This is a requirement (for more, see initramfs.bzl).
            "System.map",
        ],
        tags = ["manual"],
    )
    kernel_modules_install(
        name = name + "fallback_modules_install",
        kernel_build = name + "fallback_build",
        tags = ["manual"],
    )

    tests = []

    # Fallback to config values.
    kernel_images(
        name = name + "fallback_images",
        kernel_modules_install = name + "fallback_modules_install",
        build_initramfs = True,
        tags = ["manual"],
    )
    _initramfs_test(
        name = name + "fallback_test",
        action_mnemonic = "Initramfs",
        target_under_test = name + "fallback_images_initramfs",
        expected_compress_args = "${RAMDISK_COMPRESS}",
        expected_compress_ext = ".lz4",
    )
    tests.append(name + "fallback_test")

    kernel_images(
        name = name + "fallback_images",
        kernel_modules_install = name + "fallback_modules_install",
        build_initramfs = True,
        tags = ["manual"],
    )
    _initramfs_test(
        name = name + "fallback_test",
        action_mnemonic = "Initramfs",
        target_under_test = name + "fallback_images_initramfs",
        expected_compress_args = "${RAMDISK_COMPRESS}",
        expected_compress_ext = ".lz4",
    )
    tests.append(name + "fallback_test")

    # Fallback to config values.

    native.test_suite(
        name = name,
        tests = tests,
    )
