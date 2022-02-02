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

load(
    ":kernel.bzl",
    "kernel_build",
    "kernel_compile_commands",
    "kernel_images",
    "kernel_kythe",
    "kernel_modules_install",
)
load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load(
    ":constants.bzl",
    "aarch64_outs",
    "x86_64_outs",
)

_ARCH_CONFIGS = {
    "kernel_aarch64": {
        "build_config": "build.config.gki.aarch64",
        "outs": aarch64_outs,
    },
    "kernel_aarch64_debug": {
        "build_config": "build.config.gki-debug.aarch64",
        "outs": aarch64_outs,
    },
    "kernel_x86_64": {
        "build_config": "build.config.gki.x86_64",
        "outs": x86_64_outs,
    },
    "kernel_x86_64_debug": {
        "build_config": "build.config.gki-debug.x86_64",
        "outs": x86_64_outs,
    },
}

# Valid configs of the value of the kmi_config argument in
# `define_common_kernels`
_KMI_CONFIG_VALID_KEYS = [
    "kmi_symbol_lists",
    "trim_nonlisted_kmi",
]

# glob() must be executed in a BUILD thread, so this cannot be a global
# variable.
def _default_kmi_configs():
    """Return the default value of `kmi_configs` of [`define_common_kernels()`](#define_common_kernels).
    """
    return {
        "kernel_aarch64": {
            "kmi_symbol_lists": native.glob(["android/abi_gki_aarch64*"]),
            "trim_nonlisted_kmi": len(native.glob(["android/abi_gki_aarch64*"])) > 0,
        },
        "kernel_aarch64_debug": {
            "kmi_symbol_lists": native.glob(["android/abi_gki_aarch64*"]),
        },
    }

def _filter_keys(d, valid_keys, what):
    """Remove keys from `d` if the key is not in `valid_keys`.

    Fail if there are unknown keys in `d`.
    """
    ret = {key: value for key, value in d.items() if key in valid_keys}
    if sorted(ret.keys()) != sorted(d.keys()):
        fail("{what} contains invalid keys {invalid_keys}. Valid keys are: {valid_keys}".format(
            what = what,
            invalid_keys = [key for key in d.keys() if key not in valid_keys],
            valid_keys = valid_keys,
        ))
    return ret

def _define_kernel_build_and_full_kmi(
        name,
        visibility,
        trim_nonlisted_kmi = None,
        **kwargs):
    """Create `kernel_build` targets with and without trimming.

    If `trim_nonlisted_kmi`, also create a `{name}_full_kmi` target that does
    not trim to support ABI monitoring. If not `trim_nonlisted_kmi`, the
    `{name}_full_kmi` target is an alias to `{name}`.

    Args:
      name: name of the main `kernel_build`
      visibility: visibility of the main `kernel_build`.
        Does not apply to `{name}_full_kmi`.
      trim_nonlisted_kmi: whether `name` trims non-listed KMI
      kwargs: passthrough to `kernel_build`
    """
    kernel_build(
        name = name,
        visibility = visibility,
        trim_nonlisted_kmi = trim_nonlisted_kmi,
        **kwargs
    )
    if trim_nonlisted_kmi:
        kernel_build(
            name = name + "_full_kmi",
            trim_nonlisted_kmi = False,
            **kwargs
        )
    else:
        native.alias(
            name = name + "_full_kmi",
            actual = name,
        )

def define_common_kernels(
        kmi_configs = None,
        toolchain_version = None,
        visibility = None):
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

    Args:
      kmi_configs: A dictionary, where keys are target names, and
        values are a dictionary of configurations on the KMI.

        The content of `kmi_configs` should match the following variables in
        `build.config.gki{,-debug}.{aarch64,x86_64}`:
        - `KMI_SYMBOL_LIST`
        - `ADDITIONAL_KMI_SYMBOL_LISTS`
        - `TRIM_NONLISTED_KMI`

        The keys of the `kmi_configs` may be one of the following:
        - `kernel_aarch64`
        - `kernel_aarch64_debug`
        - `kernel_x86_64`
        - `kernel_x86_64_debug`

        The values of the `kmi_configs` should be a dictionary, where keys
        are one of the following, and values are passed to the corresponding
        argument in [`kernel_build`](#kernel_build):
        - `kmi_symbol_lists`
        - `trim_nonlisted_kmi`

        If an architecture or configuration is not specified in `kmi_configs`,
        its value is passed to `kernel_build` as `None`, so `kernel_build`
        decides its default value. See [`kernel_build`](#kernel_build) for
        the default value of each configuration.

        If `kmi_configs` is unspecified or `None`, use sensible defaults:
        - `kernel_aarch64`: Trim using `glob(["android/abi_gki_aarch64*"])`
        - `kernel_aarch64_debug`: Use `glob(["android/abi_gki_aarch64*"])` as
           KMI symbol lists, but don't trim
        - `kernel_x86_64` and `kernel_x86_64_debug`: No KMI symbol lists and
          don't trim.

        That is, the default value is:
        ```
        {
            "kernel_aarch64": {
                "kmi_symbol_lists": glob(["android/abi_gki_aarch64*"]),
                "trim_nonlisted_kmi": len(glob(["android/abi_gki_aarch64*"])) > 0,
            },
            "kernel_aarch64_debug": {
                "kmi_symbol_lists": glob(["android/abi_gki_aarch64*"]),
                # trim_nonlisted_kmi is `None`,
            },
        }
        ```
      toolchain_version: If not set, use default value in `kernel_build`.
      visibility: visibility of the kernel build. If unspecified, its default
        value is `["//visibility:public"]`.

        See [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
    """

    if visibility == None:
        visibility = ["//visibility:public"]

    if kmi_configs == None:
        kmi_configs = _default_kmi_configs()
    if kmi_configs:
        kmi_configs = _filter_keys(
            kmi_configs,
            valid_keys = _ARCH_CONFIGS.keys(),
            what = "//{package}: kmi_configs".format(package = native.package_name()),
        )

    for name, arch_config in _ARCH_CONFIGS.items():
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

        kmi_config = _filter_keys(
            kmi_configs.get(name, {}),
            valid_keys = _KMI_CONFIG_VALID_KEYS,
            what = '//{package}:{name}: kmi_configs["{name}"]'.format(
                package = native.package_name(),
                name = name,
            ),
        )
        _define_kernel_build_and_full_kmi(
            name = name,
            srcs = [name + "_sources"],
            outs = arch_config["outs"],
            implicit_outs = [
                # Kernel build time module signining utility and keys
                # Only available during GKI builds
                # Device fragments need to add: '# CONFIG_MODULE_SIG_ALL is not set'
                "scripts/sign-file",
                "certs/signing_key.pem",
                "certs/signing_key.x509",
            ],
            build_config = arch_config["build_config"],
            visibility = visibility,
            toolchain_version = toolchain_version,
            **kmi_config
        )

        kernel_modules_install(
            name = name + "_modules_install",
            kernel_build = name,
        )

        kernel_images(
            name = name + "_images",
            kernel_build = name,
            kernel_modules_install = name + "_modules_install",
            build_system_dlkm = True,
            deps = [
                # Keep the following in sync with build.config.gki* MODULES_LIST
                "android/gki_system_dlkm_modules",
            ],
        )

        # Everything in name + "_dist", minus UAPI headers, because
        # device-specific external kernel modules may install different headers.
        native.filegroup(
            name = name + "_additional_artifacts",
            srcs = [
                name + "_headers",
                name + "_modules_install",
                name + "_images",
                name + "_kmi_symbol_list",
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
