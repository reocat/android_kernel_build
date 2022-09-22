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

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
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

    Args:
      common_kernel_package: The path to the common kernel source tree. By
        default, it is `"common"`.

        Do not provide the trailing `/`.
    """
    if common_kernel_package == None:
        common_kernel_package = "common"

    import_external_repositories(
        # keep sorted
        bazel_skylib = True,
        io_abseil_py = True,
        io_bazel_stardoc = True,
    )

    # The prebuilt NDK does not support Bazel.
    # https://docs.bazel.build/versions/main/external.html#non-bazel-projects
    native.new_local_repository(
        name = "prebuilt_ndk",
        path = "prebuilts/ndk-r23",
        build_file = "build/kernel/kleaf/ndk.BUILD",
    )

    key_value_repo(
        name = "kernel_toolchain_info",
        srcs = ["//{}:build.config.constants".format(common_kernel_package)],
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

    # Fake local_jdk to avoid fetching rules_java for any exec targets.
    # See b/245624185.
    maybe(
        repo_rule = native.local_repository,
        name = "local_jdk",
        path = "build/kernel/kleaf/fake_local_jdk",
    )

    native.register_toolchains(
        "//prebuilts/build-tools:py_toolchain",
    )
