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
Tests for artifacts produced by kernel_module.
"""

load("//build/kernel/kleaf/impl:hermetic_exec.bzl", "hermetic_exec_test")
load("//build/bazel_common_rules/exec:embedded_exec.bzl", "embedded_exec")

visibility("//build/kernel/kleaf/...")

def kernel_module_test(
        name,
        modules = None,
        **kwargs):
    """A test on artifacts produced by [kernel_module](#kernel_module).

    Args:
        name: name of test
        modules: The list of `*.ko` kernel modules, or targets that produces
            `*.ko` kernel modules (e.g. [kernel_module](#kernel_module)).
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:kernel_module_test.py"
    args = []
    data = []
    if modules:
        args.append("--modules")
        args += ["$(rootpaths {})".format(module) for module in modules]
        data += modules

    _hermetic_py_test_common(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = data,
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
        **kwargs
    )

def kernel_build_test(
        name,
        target = None,
        **kwargs):
    """A test on artifacts produced by [kernel_build](#kernel_build).

    Args:
        name: name of test
        target: The [`kernel_build()`](#kernel_build).
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:kernel_build_test.py"
    args = []
    if target:
        args += ["--artifacts", "$(rootpaths {})".format(target)]

    _hermetic_py_test_common(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = [target],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
            "@io_abseil_py//absl/testing:parameterized",
        ],
        **kwargs
    )

def initramfs_modules_options_test(
        name,
        kernel_images,
        expected_modules_options,
        **kwargs):
    """Tests that initramfs has modules.options with the given content.

    Args:
        name: name of the test
        kernel_images: name of the `kernel_images` target. It must build initramfs.
        expected_modules_options: file with expected content for `modules.options`
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:initramfs_modules_options_test.py"
    args = [
        "--expected",
        "$(rootpath {})".format(expected_modules_options),
        "$(rootpaths {})".format(kernel_images),
    ]

    _hermetic_py_test_common(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = [
            expected_modules_options,
            kernel_images,
        ],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
        **kwargs
    )

def _hermetic_py_test_common(
        name,
        srcs,
        main = None,
        args = None,
        data = None,
        deps = None,
        python_version = None,
        timeout = None,
        **kwargs):

    """Drop-in replacement for `py_test` that uses hermetic toolchain.

    The test binary may find hermetic toolchain from `PATH`.
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }
    native.py_binary(
        name = name + "_binary",
        main = main,
        srcs = srcs,
        python_version = python_version,
        data = data,
        args = args,
        deps = deps,
        **private_kwargs
    )

    embedded_exec(
        name = name + "_embedded",
        actual = name + "_binary",
        **private_kwargs
    )

    hermetic_exec_test(
        name = name,
        data = [name + "_embedded"],
        script = "$(rootpath {}_embedded)".format(name),
        timeout = timeout,
        **kwargs
    )
