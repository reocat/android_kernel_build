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

"""Utilities to define a repository for kernel prebuilts."""

load(
    "//build/kernel/kleaf:constants.bzl",
    "DEFAULT_GKI_OUTS",
)
load(
    ":constants.bzl",
    "GKI_ARTIFACTS_AARCH64_OUTS",
    "MODULES_STAGING_ARCHIVE",
    "MODULE_OUTS_FILE_SUFFIX",
    "MODULE_SCRIPTS_ARCHIVE_SUFFIX",
    "SYSTEM_DLKM_COMMON_OUTS",
    "TOOLCHAIN_VERSION_FILENAME",
)

visibility("//build/kernel/kleaf/...")

# Key: name of repository in bazel.WORKSPACE
# target: Bazel target name in common_kernels.bzl
# arch: Architecture associated with this mapping.
CI_TARGET_MAPPING = {
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    "gki_prebuilts": {
        "arch": "arm64",
        "target": "kernel_aarch64",
        "protected_modules": "gki_aarch64_protected_modules",
        "gki_prebuilts_outs": GKI_ARTIFACTS_AARCH64_OUTS,

        # See common_kernels.bzl and download_repo.bzl.
        # - mandatory: If False, download errors are ignored. See workspace.bzl
        # - outs_mapping: key: local filename. value: remote_filename_fmt.
        "download_configs": [
            {
                "target_suffix": "files",
                "mandatory": True,
                "outs_mapping": {e: e for e in DEFAULT_GKI_OUTS} | {
                    "kernel_aarch64" + MODULE_OUTS_FILE_SUFFIX: "kernel_aarch64" + MODULE_OUTS_FILE_SUFFIX,
                    # FIXME these should go to ddk_artifacts to avoid being copied to $OUT_DIR
                    "kernel_aarch64" + MODULE_SCRIPTS_ARCHIVE_SUFFIX: "kernel_aarch64" + MODULE_SCRIPTS_ARCHIVE_SUFFIX,
                    # FIXME use constant
                    "kernel_aarch64" + "_internal_outs.tar.gz": "kernel_aarch64" + "_internal_outs.tar.gz",
                    "kernel_aarch64" + "_config_outdir.tar.gz": "kernel_aarch64" + "_config_outdir.tar.gz",
                    "kernel_aarch64" + "_env.sh": "kernel_aarch64" + "_env.sh",
                },
            },
            {
                "target_suffix": "uapi_headers",
                "mandatory": True,
                "outs_mapping": {
                    "kernel-uapi-headers.tar.gz": "kernel-uapi-headers.tar.gz",
                },
            },
            {
                "target_suffix": "unstripped_modules_archive",
                "mandatory": True,
                "outs_mapping": {
                    "unstripped_modules.tar.gz": "unstripped_modules.tar.gz",
                },
            },
            {
                "target_suffix": "headers",
                "mandatory": True,
                "outs_mapping": {
                    "kernel-headers.tar.gz": "kernel-headers.tar.gz",
                },
            },
            {
                "target_suffix": "images",
                "mandatory": True,
                # TODO(b/297934577): Update GKI prebuilts to download system_dlkm.<fs>.img
                "outs_mapping": {e: e for e in SYSTEM_DLKM_COMMON_OUTS},
            },
            {
                "target_suffix": "toolchain_version",
                "mandatory": True,
                "outs_mapping": {
                    TOOLCHAIN_VERSION_FILENAME: TOOLCHAIN_VERSION_FILENAME,
                },
            },
            {
                "target_suffix": "boot_img_archive",
                "mandatory": True,
                "outs_mapping": {
                    "boot-img.tar.gz": "boot-img.tar.gz",
                    # The others can be found by extracting the archive, see gki_artifacts_prebuilts
                },
            },
            {
                "target_suffix": "boot_img_archive_signed",
                # Do not fail immediately if this file cannot be downloaded, because it does not
                # exist for unsigned builds. A build error will be emitted by gki_artifacts_prebuilts
                # if --use_signed_prebuilts and --use_gki_prebuilts=<an unsigned build number>.
                "mandatory": False,
                "outs_mapping": {
                    # The basename is kept boot-img.tar.gz so it works with
                    # gki_artifacts_prebuilts. It is placed under the signed/
                    # directory to avoid conflicts with boot_img_archive in
                    # download_artifacts_repo.
                    # The others can be found by extracting the archive, see gki_artifacts_prebuilts
                    "signed/boot-img.tar.gz": "signed/certified-boot-img-{build_number}.tar.gz",
                },
            },
            {
                "target_suffix": "ddk_artifacts",
                "mandatory": True,
                "outs_mapping": {
                    # _modules_prepare
                    "modules_prepare_outdir.tar.gz": "modules_prepare_outdir.tar.gz",
                    # _modules_staging_archive
                    MODULES_STAGING_ARCHIVE: MODULES_STAGING_ARCHIVE,
            },
            {
                "target_suffix": "kmi_symbol_list",
                "mandatory": False,
                "outs_mapping": {
                    "abi_symbollist": "abi_symbollist",
                    "abi_symbollist.report": "abi_symbollist.report",
                },
            },
        ],
    },
}

def get_prebuilt_build_file_fragment(
        target,
        download_configs,
        gki_prebuilts_outs,
        arch,
        protected_modules,
        collect_unstripped_modules,
        module_outs_file_suffix,
        toolchain_version_filename):
    """Helper function to generate a BUILD file for kernel prebuilts.

    Args:
        arch: Architecture associated with this mapping.
        target: Bazel target name in common_kernels.bzl
        gki_prebuilts_outs: List of output files from gki_artifacts()
        download_configs: For each key-value pair, the key is
            target suffix, and the value are the list of files for that target.
            Define a filegroup named `{target}_{target_suffix}` with the
            given list of files.
        protected_modules: file name of the protected modules list
        collect_unstripped_modules: value of `collect_unstripped_modules` for `kernel_filegroup`
        module_outs_file_suffix: suffix of file that lists `module_outs`
        toolchain_version_filename: filename for defining toolchain version

    Returns:
        string that represents a BUILD file for kernel prebuilts.
    """
    content = ""

    # suffixed_target_outs: outs of target named {name}_{target_suffix}
    for target_suffix, suffixed_target_outs in download_configs.items():
        content += """\

filegroup(
    name = "{suffixed_target}",
    srcs = {suffixed_target_outs_repr},
    visibility = ["//visibility:private"],
)
""".format(
            suffixed_target = target + "_" + target_suffix,
            suffixed_target_outs_repr = repr(suffixed_target_outs),
        )

    content += """\

gki_artifacts_prebuilts(
    name = "{target}_gki_artifacts",
    srcs = select({{
        "{use_signed_prebuilts_is_true}": ["{target}_boot_img_archive_signed"],
        "//conditions:default": ["{target}_boot_img_archive"],
    }}),
    outs = {gki_prebuilts_outs},
    visibility = ["//visibility:private"],
)
""".format(
        target = target,
        use_signed_prebuilts_is_true = Label("//build/kernel/kleaf:use_signed_prebuilts_is_true"),
        gki_prebuilts_outs = repr(gki_prebuilts_outs),
    )

    # FIXME handle clang version for kernel_filegroup
    target_platform = Label("//build/kernel/kleaf/impl:android_{}".format(arch))
    exec_platform = Label("//build/kernel/kleaf/impl:linux_x86_64")

    content += """\

kernel_filegroup(
    name = "{target}",
    srcs = [":{target}_files"],
    target_platform = "{target_platform}",
    exec_platform = "{exec_platform}",
    deps = [
        ":{target}_ddk_artifacts",
        ":{target}_unstripped_modules_archive",
        ":{target}_{toolchain_version_filename}",
    ],
    kernel_uapi_headers = "{target}_uapi_headers",
    collect_unstripped_modules = {collect_unstripped_modules},
    images = "{target}_images",
    module_outs_file = "{module_outs_file}",
    protected_modules_list = {protected_modules_repr},
    gki_artifacts = ":{target}_gki_artifacts",
    visibility = ["//visibility:public"],
)
""".format(
        target = target,
        target_platform = target_platform,
        exec_platform = exec_platform,
        toolchain_version_filename = toolchain_version_filename,
        collect_unstripped_modules = collect_unstripped_modules,
        module_outs_file = target + module_outs_file_suffix,
        protected_modules_repr = repr(protected_modules),
    )

    content += """\

filegroup(
    name = "{target}_additional_artifacts",
    srcs = {additional_artifacts_items_repr},
)
""".format(
        target = target,
        additional_artifacts_items_repr = repr([
            target + "_headers",
            target + "_images",
            target + "_kmi_symbol_list",
            target + "_gki_artifacts",
        ]),
    )
    return content
