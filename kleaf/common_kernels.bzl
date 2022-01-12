# Copyright (C) 2021 The Android Open Source Project
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

load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load(
    "//build/kleaf:kernel.bzl",
    "kernel_build",
    "kernel_compile_commands",
    "kernel_filegroup",
    "kernel_images",
    "kernel_kythe",
    "kernel_modules_install",
)
load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load(
    "//build/kleaf:constants.bzl",
    "DOWNLOAD_TARGET_SUFFIX_TO_OUTPUTS",
    "aarch64_outs",
    "x86_64_outs",
)
load(
    "//build/kleaf:utils.bzl",
    "sanitize_repo_name",
)

_ARCH_CONFIGS = [
    (
        "kernel_aarch64",
        "build.config.gki.aarch64",
        aarch64_outs,
    ),
    (
        "kernel_aarch64_debug",
        "build.config.gki-debug.aarch64",
        aarch64_outs,
    ),
    (
        "kernel_x86_64",
        "build.config.gki.x86_64",
        x86_64_outs,
    ),
    (
        "kernel_x86_64_debug",
        "build.config.gki-debug.x86_64",
        x86_64_outs,
    ),
]

def define_common_kernels(
        toolchain_version = None,
        visibility = [
            "//visibility:public",
        ]):
    """Defines common build targets for Android Common Kernels.

    This macro expands to the commonly defined common kernels (such as the GKI
    kernels and their variants. They are defined based on the conventionally
    used `BUILD_CONFIG` file and produce usual output files.

    Targets declared for kernel build (parent list item depends on child list item):
    - `kernel_aarch64_sources`
    - `kernel_aarch64_dist`
      - `kernel_aarch64`
      - `kernel_aarch64_uapi_headers`
      - `kernel_aarch64_additional_artifacts`
    - `kernel_aarch64_debug_dist`
      - `kernel_aarch64_debug`
    - `kernel_x86_64_sources`
    - `kernel_x86_64_dist`
      - `kernel_x86_64`
      - `kernel_x86_64_uapi_headers`
      - `kernel_x86_64_additional_artifacts`
    - `kernel_x86_64_debug_dist`
      - `kernel_x86_64_debug`

    `<name>` (aka `kernel_{aarch64,x86}{_debug,}`) targets build the
    main kernel build artifacts, e.g. `vmlinux`, etc.

    `<name>_sources` are convenience filegroups that refers to all sources required to
    build `<name>` and related targets.

    `<name>_uapi_headers` targets build `kernel-uapi-headers.tar.gz`.

    `<name>_additional_artifacts` contains additional artifacts that may be added to
    a distribution. This includes:
      - Images, including `system_dlkm`, etc.
      - `kernel-headers.tar.gz`

    `<name>_dist` targets can be run to obtain a distribution outside the workspace.

    Aliases are created to refer to the GKI kernel (`kernel_aarch64`) as
    "`kernel`" and the corresponding dist target (`kernel_aarch64_dist`) as
    "`kernel_dist`".

    Targets declared for cross referencing:
    - `kernel_aarch64_kythe_dist`
      - `kernel_aarch64_kythe`

    **Prebuilts**

    In addition, a
    [`bool_flag`](https://github.com/bazelbuild/bazel-skylib/blob/main/docs/common_settings_doc.md)
    named `use_prebuilt_gki` is defined. An alias is already created in `common.bazelrc`, so you
    may use `--use_prebuilt_gki` as a shorthand for `--//common:use_prebuilt_gki`.

    If the `use_prebuilt_gki` flag is set, the build number must also be set. For example:

    ```
    bazel build --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER_MAP="gki_prebuilts=<build_number>" <targets>
    ```

    The build number may also be set to a fixed value in `device.bazelrc`. If so, you do not
    need to specify it every time in the command line. For example:

    ```
    # device.bazelrc
    build --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER_MAP="gki_prebuilts=8077484"
    ```

    `<name>_download_or_build` targets builds `<name>` from source if the `use_prebuilt_gki`
    is not set, and downloads artifacts of the build number from
    [ci.android.com](http://ci.android.com) if it is set. The build number is spe

    - `kernel_aarch64_download_or_build`
      - `kernel_aarch64_headers_download_or_build`
      - `kernel_aarch64_uapi_headers_download_or_build`
      - `kernel_aarch64_images_download_or_build`

    Note: If a device should build against downloaded prebuilts unconditionally, set
    `--use_prebuilt_gki` and a fixed build number in `device.bazelrc`. For example:
    ```
    # device.bazelrc
    build --//common:use_prebuilt_gki
    build --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER_MAP="gki_prebuilts=8077484"
    ```

    Args:
      toolchain_version: If not set, use default value in `kernel_build`.
      visibility: visibility of the `kernel_build` and targets defined for downloaded prebuilts.

        See [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
    """

    kernel_build_kwargs = {}
    if toolchain_version:
        kernel_build_kwargs["toolchain_version"] = toolchain_version

    for name, config, outs in _ARCH_CONFIGS:
        native.filegroup(
            name = name + "_sources",
            srcs = native.glob(
                ["**"],
                exclude = [
                    "BUILD.bazel",
                    "**/*.bzl",
                    ".git/**",
                ],
            ),
        )

        kernel_build(
            name = name,
            srcs = [name + "_sources"],
            outs = outs,
            build_config = config,
            visibility = visibility,
            **kernel_build_kwargs
        )

        kernel_modules_install(
            name = name + "_modules_install",
            kernel_build = name,
        )

        kernel_images(
            name = name + "_images",
            kernel_build = name,
            kernel_modules_install = name + "_modules_install",
            # Sync with DOWNLOAD_TARGET_SUFFIX_TO_OUTPUTS["images"].
            build_system_dlkm = True,
        )

        # Everything in name + "_dist", minus UAPI headers, because
        # device-specific external kernel modules may install different headers.
        native.filegroup(
            name = name + "_additional_artifacts",
            srcs = [
                name + "_headers",
                name + "_modules_install",
                name + "_images",
            ],
        )

        copy_to_dist_dir(
            name = name + "_dist",
            data = [
                name,
                name + "_uapi_headers",
                name + "_additional_artifacts",
            ],
            flat = True,
        )

    native.alias(
        name = "kernel",
        actual = ":kernel_aarch64",
    )

    native.alias(
        name = "kernel_dist",
        actual = ":kernel_aarch64_dist",
    )

    kernel_compile_commands(
        name = "kernel_aarch64_compile_commands",
        kernel_build = ":kernel_aarch64",
    )

    kernel_kythe(
        name = "kernel_aarch64_kythe",
        kernel_build = ":kernel_aarch64",
        compile_commands = ":kernel_aarch64_compile_commands",
    )

    copy_to_dist_dir(
        name = "kernel_aarch64_kythe_dist",
        data = [
            ":kernel_aarch64_compile_commands",
            ":kernel_aarch64_kythe",
        ],
        flat = True,
    )

    _define_prebuilts(visibility = visibility)

# (Bazel target name, repo prefix in bazel.WORKSPACE, outs)
_CI_TARGET_MAPPING = [
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    ("kernel_aarch64", "gki_prebuilts", aarch64_outs),
]

def _define_prebuilts(**kwargs):
    # Build number for GKI prebuilts
    bool_flag(
        name = "use_prebuilt_gki",
        build_setting_default = False,
    )

    # Matches when --use_prebuilt_gki is set.
    native.config_setting(
        name = "use_prebuilt_gki_set",
        flag_values = {
            ":use_prebuilt_gki": "true",
        },
    )

    for name, repo_prefix, outs in _CI_TARGET_MAPPING:
        source_package_name = ":" + name

        native.filegroup(
            name = name + "_downloaded",
            srcs = ["@{}_{}//file".format(repo_prefix, sanitize_repo_name(filename)) for filename in outs],
        )

        # A kernel_filegroup that:
        # - If --use_prebuilt_gki_num is set, use downloaded prebuilt of kernel_aarch64
        # - Otherwise build kernel_aarch64 from sources.
        kernel_filegroup(
            name = name + "_download_or_build",
            srcs = select({
                ":use_prebuilt_gki_set": [":" + name + "_downloaded"],
                "//conditions:default": [source_package_name],
            }),
            **kwargs
        )

        for suffix, files in DOWNLOAD_TARGET_SUFFIX_TO_OUTPUTS:
            native.filegroup(
                name = name + "_" + suffix + "_downloaded",
                srcs = ["@{}_{}//file".format(repo_prefix, sanitize_repo_name(filename)) for filename in files],
            )

            # A filegroup that:
            # - If --use_prebuilt_gki_num is set, use downloaded prebuilt of kernel_{arch}_{suffix}
            # - Otherwise build kernel_{arch}_{suffix}
            native.filegroup(
                name = name + "_" + suffix + "_download_or_build",
                srcs = select({
                    ":use_prebuilt_gki_set": [":" + name + "_" + suffix + "_downloaded"],
                    "//conditions:default": [source_package_name + "_" + suffix],
                }),
                **kwargs
            )
