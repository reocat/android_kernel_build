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

load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load("//build/bazel_common_rules/exec:exec.bzl", "exec")

def kernel_build_abi_dist(
        name,
        kernel_abi = None,
        kernel_build_abi = None,
        **kwargs):
    """A wrapper over `copy_to_dist_dir` for [`kernel_build_abi`](#kernel_build_abi).

    After copying all files to dist dir, return the exit code from `diff_abi`.

    Args:
      name: name of the dist target
      kernel_abi: name of the [`kernel_abi`](#kernel_abi) invocation.
      kernel_build_abi: **Deprecated**. Use `kernel_abi` instead.

        Name of the [`kernel_build_abi`](#kernel_build_abi) invocation. If `kernel_abi` is set
        directly, this argument is ignored.
      **kwargs: passed to `copy_to_dist_dir`.
    """

    # TODO(b/231647455): Clean up hard-coded name "_abi" and "_abi_diff_executable".

    if kernel_abi == None:
        if kernel_build_abi == None:
            fail("//{}:{}: kernel_abi must be set.".format(native.package_name(), name))
        kernel_abi = kernel_build_abi + "_abi"

    if kwargs.get("data") == None:
        kwargs["data"] = []

    # Use explicit + to prevent modifying the original list.
    kwargs["data"] = kwargs["data"] + [kernel_abi]

    copy_to_dist_dir(
        name = name + "_copy_to_dist_dir",
        **kwargs
    )

    exec(
        name = name,
        data = [
            name + "_copy_to_dist_dir",
            kernel_abi + "_diff_executable",
        ],
        script = """
          # Copy to dist dir
            $(rootpath {copy_to_dist_dir}) $@
          # Check return code of diff_abi and kmi_enforced
            $(rootpath {diff})
        """.format(
            copy_to_dist_dir = name + "_copy_to_dist_dir",
            diff = kernel_abi + "_diff_executable",
        ),
    )
