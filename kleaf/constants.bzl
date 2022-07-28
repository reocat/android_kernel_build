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

load(
    "//build/kernel/kleaf/impl:constants.bzl",
    "MODULE_OUTS_FILE_OUTPUT_GROUP",
    "MODULE_OUTS_FILE_SUFFIX",
    "TOOLCHAIN_VERSION_FILENAME",
)

_common_outs = [
    "System.map",
    "modules.builtin",
    "modules.builtin.modinfo",
    "vmlinux",
    "vmlinux.symvers",
]

_AARCH64_IMAGES = [
    "Image",
    "Image.lz4",
    "Image.gz",
]

# Common output files for aarch64 kernel builds.
aarch64_outs = _common_outs + _AARCH64_IMAGES

aarch64_gz_outs = _common_outs + [
    "Image",
    "Image.gz",
]

# Common output files for x86_64 kernel builds.
x86_64_outs = _common_outs + ["bzImage"]

# Sync with gki_artifacts.bzl
_AARCH64_GKI_ARTIFACTS_OUTS = [
    "boot-img.tar.gz",
    "gki-info.txt",
] + [
    "boot.img" if e == "Image" else "boot-{}.img".format(e[len("Image."):])
    for e in _AARCH64_IMAGES
]

# See common_kernels.bzl.
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
        "outs": [
            # Sync with system_dlkm_image.bzl
            "system_dlkm.img",
            "system_dlkm_staging_archive.tar.gz",
            "system_dlkm.modules.load",
        ],
    },
    {
        "target_suffix": "gki_artifacts",
        # We only download GKI for arm64, not x86_64
        # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
        "outs": _AARCH64_GKI_ARTIFACTS_OUTS,
    },
    {
        "target_suffix": "ddk_artifacts",
        "outs": [
            # _modules_prepare
            "modules_prepare_outdir.tar.gz",
            # _modules_staging_archive
            "modules_staging_dir.tar.gz",
        ],
    },
]

# Key: Bazel target name in common_kernels.bzl
# repo_name: name of download_artifacts_repo in bazel.WORKSPACE
# outs: list of outs associated with that target name
CI_TARGET_MAPPING = {
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    "kernel_aarch64": {
        "repo_name": "gki_prebuilts",
        "outs": aarch64_outs + [
            TOOLCHAIN_VERSION_FILENAME,
            "kernel_aarch64" + MODULE_OUTS_FILE_SUFFIX,
        ],
    },
}

LTO_VALUES = (
    "default",
    "none",
    "thin",
    "full",
)
