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
    "//build/kernel/kleaf:download_repo.bzl",
    "download_artifacts_repo",
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

# Always collect_unstripped_modules for common kernels.
# Sync with common_kernels.bzl
# TODO(b/298416462): This should be determined by downloaded artifacts.
_COLLECT_UNSTRIPPED_MODULES = True

# See common_kernels.bzl and download_repo.bzl.
# - mandatory: If False, download errors are ignored. Default is True; see workspace.bzl
GKI_DOWNLOAD_CONFIGS = [
    {
        "target_suffix": "uapi_headers",
        "outs": [
            "kernel-uapi-headers.tar.gz",
        ],
    },
    {
        "target_suffix": "unstripped_modules_archive",
        "outs": [
            "unstripped_modules.tar.gz",
        ],
    },
    {
        "target_suffix": "headers",
        "outs": [
            "kernel-headers.tar.gz",
        ],
    },
    {
        "target_suffix": "images",
        # TODO(b/297934577): Update GKI prebuilts to download system_dlkm.<fs>.img
        "outs": SYSTEM_DLKM_COMMON_OUTS,
    },
    {
        "target_suffix": "toolchain_version",
        "outs": [
            TOOLCHAIN_VERSION_FILENAME,
        ],
    },
    {
        "target_suffix": "boot_img_archive",
        # We only download GKI for arm64, not riscv64 or x86_64
        # TODO(b/206079661): Allow downloaded prebuilts for risc64/x86_64/debug targets.
        "outs": [
            "boot-img.tar.gz",
            # The others can be found by extracting the archive, see gki_artifacts_prebuilts
        ],
    },
    {
        "target_suffix": "boot_img_archive_signed",
        # Do not fail immediately if this file cannot be downloaded, because it does not
        # exist for unsigned builds. A build error will be emitted by gki_artifacts_prebuilts
        # if --use_signed_prebuilts and --use_gki_prebuilts=<an unsigned build number>.
        "mandatory": False,
        # We only download GKI for arm64, not riscv64 or x86_64
        # TODO(b/206079661): Allow downloaded prebuilts for risc64/x86_64/debug targets.
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
        "outs": [
            # _modules_prepare
            "modules_prepare_outdir.tar.gz",
            # _modules_staging_archive
            MODULES_STAGING_ARCHIVE,
            # _ddk_headers_archive
            # We only download GKI for arm64, not riscv64 or x86_64
            # TODO(b/206079661): Allow downloaded prebuilts for risc64/x86_64/debug targets.
            # "kernel_aarch64_ddk_headers_archive.tar.gz",
        ],
    },
    {
        "target_suffix": "kmi_symbol_list",
        "mandatory": False,
        "outs": [
            "abi_symbollist",
            "abi_symbollist.report",
        ],
    },
]

# Key: name of repository
# repo_name: name of download_artifacts_repo in bazel.WORKSPACE
# outs: list of outs associated with that target name
# arch: Architecture associated with this mapping.
CI_TARGET_MAPPING = {
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    "gki_prebuilts": {
        "arch": "arm64",
        # TODO: Rename this when more architectures are added.
        "target": "kernel_aarch64",
        "outs": DEFAULT_GKI_OUTS + [
            "kernel_aarch64" + MODULE_OUTS_FILE_SUFFIX,
            # FIXME these should go to ddk_artifacts to avoid being copied to $OUT_DIR
            "kernel_aarch64" + MODULE_SCRIPTS_ARCHIVE_SUFFIX,
            # FIXME use constant
            "kernel_aarch64" + "_internal_outs.tar.gz",
            "kernel_aarch64" + "_config_outdir.tar.gz",
            "kernel_aarch64" + "_env.sh",
        ],
        "protected_modules": "gki_aarch64_protected_modules",
        "gki_prebuilts_outs": GKI_ARTIFACTS_AARCH64_OUTS,
    },
}

def kernel_prebuilt_repo(
        name,
        artifact_url_fmt):
    """Define a repository that downloads kernel prebuilts.

    Args:
        name: name of repository
        artifact_url_fmt: see [`define_kleaf_workspace.artifact_url_fmt`](#define_kleaf_workspace-artifact_url_fmt)
    """
    mapping = CI_TARGET_MAPPING[name]
    target = mapping["target"]
    main_target_outs = mapping["outs"]

    gki_prebuilts_files = {out: None for out in mapping["outs"]}
    gki_prebuilts_optional_files = {mapping["protected_modules"]: None}
    for config in GKI_DOWNLOAD_CONFIGS:
        if config.get("mandatory", True):
            files_dict = gki_prebuilts_files
        else:
            files_dict = gki_prebuilts_optional_files

        files_dict.update({out: None for out in config.get("outs", [])})

        for out, remote_filename_fmt in config.get("outs_mapping", {}).items():
            file_metadata = {"remote_filename_fmt": remote_filename_fmt}
            files_dict.update({out: file_metadata})

    extra_build_file_content = """\
# Generated file. DO NOT EDIT.

\"""Prebuilts for {target}.
\"""

load("{kernel_bzl}", "kernel_filegroup")
load("{gki_artifacts_bzl}", "gki_artifacts_prebuilts")
""".format(
        kernel_bzl = Label("//build/kernel/kleaf:kernel.bzl"),
        gki_artifacts_bzl = Label("//build/kernel/kleaf/impl:gki_artifacts.bzl"),
        target = target,
    )

    for config in GKI_DOWNLOAD_CONFIGS:
        target_suffix = config["target_suffix"]

        # outs of target named {name}_{target_suffix}
        suffixed_target_outs = list(config.get("outs", []))
        suffixed_target_outs += list(config.get("outs_mapping", {}).keys())

        extra_build_file_content += """\

filegroup(
    name = "{suffixed_target}",
    srcs = {suffixed_target_outs_repr},
    tags = ["manual"],
    visibility = ["//visibility:private"],
)
""".format(
            suffixed_target = target + "_" + target_suffix,
            suffixed_target_outs_repr = repr(["//{}".format(elem) for elem in suffixed_target_outs]),
        )

    extra_build_file_content += """\

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
        gki_prebuilts_outs = repr(mapping["gki_prebuilts_outs"]),
    )

    # FIXME handle clang version for kernel_filegroup
    target_platform = Label("//build/kernel/kleaf/impl:android_{}".format(mapping["arch"]))
    exec_platform = Label("//build/kernel/kleaf/impl:linux_x86_64")

    extra_build_file_content += """\

kernel_filegroup(
    name = "{target}",
    srcs = {main_target_outs_repr},
    target_platform = "{target_platform}",
    exec_platform = "{exec_platform}",
    deps = [
        ":{target}_ddk_artifacts",
        ":{target}_unstripped_modules_archive",
        ":{target}_{toolchain_version_filename}",
    ],
    kernel_uapi_headers = "{target}_uapi_headers_download_or_build",
    collect_unstripped_modules = {collect_unstripped_modules},
    images = "{target}_images_download_or_build",
    module_outs_file = "//{target}{module_outs_file_suffix}",
    protected_modules_list = "//{protected_modules}",
    gki_artifacts = "{target}_gki_artifacts",
    visibility = ["//visibility:public"],
)
""".format(
        target = target,
        main_target_outs_repr = repr(["//{}".format(elem) for elem in main_target_outs]),
        target_platform = target_platform,
        exec_platform = exec_platform,
        toolchain_version_filename = TOOLCHAIN_VERSION_FILENAME,
        collect_unstripped_modules = _COLLECT_UNSTRIPPED_MODULES,
        module_outs_file_suffix = MODULE_OUTS_FILE_SUFFIX,
        protected_modules = mapping["protected_modules"],
    )

    extra_build_file_content += """\

filegroup(
    name = "{target}_additional_artifacts",
    srcs = {additional_artifacts_items_repr},
)
""".format(
        additional_artifacts_items_repr = repr([
            target + "_headers",
            target + "_images",
            target + "_kmi_symbol_list",
            target + "_gki_artifacts",
        ]),
    )

    download_artifacts_repo(
        name = name,
        files = gki_prebuilts_files,
        optional_files = gki_prebuilts_optional_files,
        target = target,
        artifact_url_fmt = artifact_url_fmt,
        extra_build_file_content = extra_build_file_content,
    )
