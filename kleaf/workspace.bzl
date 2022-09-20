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

load("//build/bazel_common_rules/workspace:external.bzl", "import_external_repositories")
load(
    "//build/kernel/kleaf:constants.bzl",
    "CI_TARGET_MAPPING",
    "GKI_DOWNLOAD_CONFIGS",
)
load("//build/kernel/kleaf:download_repo.bzl", "download_artifacts_repo")
load("//build/kernel/kleaf:key_value_repo.bzl", "key_value_repo")

def define_kleaf_workspace(common_kernel_package = None):
    """Common macro for defining repositories in a Kleaf workspace.

    **This macro must only be called from `WORKSPACE` or `WORKSPACE.bazel`
    files, not `BUILD` or `BUILD.bazel` files!**

    If [`define_kleaf_workspace_epilog`](#define_kleaf_workspace_epilog) is
    called, it must be called after `define_kleaf_workspace` is called.

    Example: assume the following directory structure:
    ```
    kernel
    |- WORKSPACE.bazel
    |- common
    `- build
       `- kernel
          `- kleaf
             `- workspace.bzl
    ```

    Then `kernel/WORKSPACE.bazel` may be a symlink to `build/kernel/kleaf/bazel.WORKSPACE`.

    Example: assume the following directory structure:
    ```
    kernel
    |- WORKSPACE.bazel
    |- aosp  ---------------- <common kernel source tree>
    `- build
       `- kernel
          `- kleaf
             `- workspace.bzl
    ```

    Then, in `kernel/WORKSPACE.bazel`, you may define:

    ```
    workspace(name = "kleaf")
    load("//build/kernel/kleaf:workspace.bzl", "define_kleaf_workspace")
    define_kleaf_workspace(
        common_kernel_package = "aosp"
    )
    load("//build/kernel/kleaf:workspace_epilog.bzl", "define_kleaf_workspace_epilog")
    define_kleaf_workspace_epilog()
    ```

    Args:
      common_kernel_package: The path to the common kernel source tree. By
        default, it is `"common"`.

        Do not provide the trailing `/`.
    """
    _define_kleaf_workspace_internal(
        common_kernel_package = common_kernel_package,
    )

def define_kleaf_as_subworkspace(
        workspace_root,
        workspace_name,
        common_kernel_package = None):
    """Common macro for defining repositories in a Kleaf subworkspace.

    **This macro must only be called from `WORKSPACE` or `WORKSPACE.bazel`
    files, not `BUILD` or `BUILD.bazel` files!**

    If [`define_kleaf_workspace_epilog`](#define_kleaf_workspace_epilog) is
    called, it must be called after `define_kleaf_workspace_subworkspace` is called.


    Example: assume the following directory structure:
    ```
    root
    |- WORKSAPCE.bazel
    `- kernel
       |- WORKSPACE.bazel
       |- common
       `- build
          `- kernel
             `- kleaf
                `- workspace.bzl
    ```

    Then, in `root/WORKSPACE.bazel`, you may define:

    ```
    workspace(name = "android")

    local_repository(
        name = "kleaf",
        path = "kernel",
    )

    load("@kleaf//build/kernel/kleaf:workspace.bzl", "define_kleaf_as_subworkspace")
    define_kleaf_as_subworkspace(
        workspace_name = "kleaf",
        workspace_root = "kernel",
    )
    ```

    Args:
      common_kernel_package: See
        [define_kleaf_workspace.common_kernel_package](#define_kleaf_workspace-common_kernel_package)
      workspace_root: Root under which kernel source tree may be found, relative
        to the main workspace.
      workspace_name: name of the subworkspace
    """
    _define_kleaf_workspace_internal(
        workspace_root = workspace_root,
        workspace_name = workspace_name,
        common_kernel_package = common_kernel_package,
    )

# TODO(b/242752091): Ensure that all Kleaf WORKSPACE defines workspace(name = "kleaf"),
# then drop the workspace_name == "" branch.
def _define_kleaf_workspace_internal(
        workspace_root = None,
        workspace_name = None,
        common_kernel_package = None):
    workspace_prefix = workspace_root or ""
    if workspace_prefix:
        workspace_prefix += "/"

    if common_kernel_package == None:
        common_kernel_package = "common"

    import_external_repositories(
        workspace_root = workspace_root,
        # keep sorted
        bazel_skylib = True,
        io_abseil_py = True,
        io_bazel_stardoc = True,
    )

    # The prebuilt NDK does not support Bazel.
    # https://docs.bazel.build/versions/main/external.html#non-bazel-projects
    native.new_local_repository(
        name = "prebuilt_ndk",
        path = "{}prebuilts/ndk-r23".format(workspace_prefix),
        build_file = "{}build/kernel/kleaf/ndk.BUILD".format(workspace_prefix),
    )

    key_value_repo(
        name = "kernel_toolchain_info",
        srcs = ["@{}//{}:build.config.constants".format(workspace_name, common_kernel_package)],
        additional_values = {
            "common_kernel_package": common_kernel_package,
        },
    )

    gki_prebuilts_files = []
    gki_prebuilts_optional_files = []
    gki_prebuilts_files += CI_TARGET_MAPPING["kernel_aarch64"]["outs"]
    for config in GKI_DOWNLOAD_CONFIGS:
        if config.get("mandatory", True):
            gki_prebuilts_files += config["outs"]
        else:
            gki_prebuilts_optional_files += config["outs"]

    download_artifacts_repo(
        name = "gki_prebuilts",
        files = gki_prebuilts_files,
        optional_files = gki_prebuilts_optional_files,
        target = "kernel_kleaf",
    )

    native.register_toolchains(
        "//prebuilts/build-tools:py_toolchain",
    )
