# Build configs

This document provides reference to the Bazel equivalent or alternative for
build configs that `build.sh` and `build_abi.sh` supports.

## Table of contents

* [`BUILD_CONFIG`](#build-config)
* [`BUILD_CONFIG_FRAGMENTS`](#build-config-fragments)
* [`FAST_BUILD`](#fast-build)
* [`OUT_DIR`](#out-dir)
* [`DIST_DIR`](#dist-dir)
* [`MAKE_GOALS`](#make-goals)
* [`EXT_MODULES`](#ext-modules)
* [`EXT_MODULES_MAKEFILE`](#ext-modules-makefile)
* [`KCONFIG_EXT_PREFIX`](#kconfig-ext-prefix)
* [`UNSTRIPPED_MODULES`](#unstripped-modules)
* [`COMPRESS_UNSTRIPPED_MODULES`](#compress-unstripped-modules)
* [`COMPRESS_MODULES`](#compress-modules)
* [`LD`](#ld)
* [`HERMETIC_TOOLCHAIN`](#hermetic-toolchain)
* [`ADDITIONAL_HOST_TOOLS`](#additional-host-tools)
* [`ABI_DEFINITION`](#abi-definition)
* [`KMI_SYMBOL_LIST`](#kmi-symbol-list)
* [`ADDITIONAL_KMI_SYMBOL_LISTS`](#additional-kmi-symbol-lists)
* [`KMI_ENFORCED`](#kmi-enforced)
* [`GENERATE_VMLINUX_BTF`](#generate-vmlinux-btf)
* [`SKIP_MRPROPER`](#skip-mrproper)
* [`SKIP_DEFCONFIG`](#skip-defconfig)
* [`SKIP_IF_VERSION_MATCHES`](#skip-if-version-matches)
* [`PRE_DEFCONFIG_CMDS`](#pre-defconfig-cmds)
* [`POST_DEFCONFIG_CMDS`](#post-defconfig-cmds)
* [`POST_KERNEL_BUILD_CMDS`](#post-kernel-build-cmds)
* [`LTO`](#lto)
* [`TAGS_CONFIG`](#tags-config)
* [`IN_KERNEL_MODULES`](#in-kernel-modules)
* [`SKIP_EXT_MODULES`](#skip-ext-modules)
* [`DO_NOT_STRIP_MODULES`](#do-not-strip-modules)
* [`EXTRA_CMDS`](#extra-cmds)
* [`DIST_CMDS`](#dist-cmds)
* [`SKIP_CP_KERNEL_HDR`](#skip-cp-kernel-hdr)
* [`BUILD_BOOT_IMG`](#build-boot-img)
* [`BUILD_VENDOR_BOOT_IMG`](#build-vendor-boot-img)
* [`SKIP_VENDOR_BOOT`](#skip-vendor-boot)
* [`VENDOR_RAMDISK_CMDS`](#vendor-ramdisk-cmds)
* [`SKIP_UNPACKING_RAMDISK`](#skip-unpacking-ramdisk)
* [`AVB_SIGN_BOOT_IMG`](#avb-sign-boot-img)
* [`AVB_BOOT_PARTITION_SIZE`](#avb-boot-partition-size)
* [`AVB_BOOT_KEY`](#avb-boot-key)
* [`AVB_BOOT_ALGORITHM`](#avb-boot-algorithm)
* [`AVB_BOOT_PARTITION_NAME`](#avb-boot-partition-name)
* [`BUILD_INITRAMFS`](#build-initramfs)
* [`MODULES_OPTIONS`](#modules-options)
* [`MODULES_ORDER`](#modules-order)
* [`GKI_MODULES_LIST`](#gki-modules-list)
* [`VENDOR_DLKM_MODULES_LIST`](#vendor-dlkm-modules-list)
* [`VENDOR_DLKM_MODULES_BLOCKLIST`](#vendor-dlkm-modules-blocklist)
* [`VENDOR_DLKM_PROPS`](#vendor-dlkm-props)
* [`LZ4_RAMDISK`](#lz4-ramdisk)
* [`LZ4_RAMDISK_COMPRESS_ARGS`](#lz4-ramdisk-compress-args)
* [`TRIM_NONLISTED_KMI`](#trim-nonlisted-kmi)
* [`KMI_SYMBOL_LIST_STRICT_MODE`](#kmi-symbol-list-strict-mode)
* [`KMI_STRICT_MODE_OBJECTS`](#kmi-strict-mode-objects)
* [`GKI_DIST_DIR`](#gki-dist-dir)
* [`GKI_BUILD_CONFIG`](#gki-build-config)
* [`GKI_PREBUILTS_DIR`](#gki-prebuilts-dir)
* [`BUILD_DTBO_IMG`](#build-dtbo-img)

## `BUILD_CONFIG`

```python
kernel_build(build_config = ...)
```

See [documentation for all rules].

## `BUILD_CONFIG_FRAGMENTS`

```python
kernel_build_config()
```

See [documentation for all rules].

## `FAST_BUILD`

Not customizable in Bazel.

You may disable LTO or use thin LTO; see [`LTO`](#LTO).

You may build just the kernel binary and GKI modules, without headers
and installing modules by building the `kernel_build` target, e.g.

```shell
$ bazel build //common:kernel_aarch64
```

## `OUT_DIR`

Not customizable in Bazel. 

You may customize [`DIST_DIR`](#dist-dir).

## `DIST_DIR`

You may specify it statically with

```python
copy_to_dist_dir(dist_dir = ...)
```

You may override it at build time with `--dist_dir`:

```shell
$ bazel run ..._dist -- --dist_dir=...
```

See [documentation for all rules].

## `MAKE_GOALS`

Specify in the build config.

## `EXT_MODULES`

```python
kernel_module()
```

See [documentation for all rules].

## `EXT_MODULES_MAKEFILE`

Not customizable in Bazel.

Reason: `EXT_MODULES_MAKEFILE` supports building external kernel modules
in parallel. This is naturally supported in Bazel.


## `KCONFIG_EXT_PREFIX`

```python
kernel_build(kconfig_ext = ...)
```

See [documentation for all rules].

## `UNSTRIPPED_MODULES`

```python
kernel_build(collect_unstripped_modules = ...)
kernel_filegroup(collect_unstripped_modules = ...)
```

See [documentation for all rules].

## `COMPRESS_UNSTRIPPED_MODULES`

```python
kernel_unstripped_modules_archive()
```

See [documentation for all rules].

## `COMPRESS_MODULES`

Not supported. Contact [owners](../OWNERS) if you need support for this config.

## `LD`

Not customizable in Bazel. Its value cannot be changed.

## `HERMETIC_TOOLCHAIN`

Not customizable in Bazel.

Reason: This is the default for Bazel builds. Its value cannot be changed.

## `ADDITIONAL_HOST_TOOLS`

Not customizable in Bazel.

Reason: The list of host tools are fixed and specified in `hermetic_tools()`.

See [documentation for all rules].

## `ABI_DEFINITION`

```python
kernel_build_abi(abi_definition = ...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## `KMI_SYMBOL_LIST`

```python
kernel_build(kmi_symbol_list = ...)
kernel_build_abi(kmi_symbol_list = ...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## `ADDITIONAL_KMI_SYMBOL_LISTS`

```python
kernel_build(additional_kmi_symbol_lists = ...)
kernel_build_abi(additional_kmi_symbol_lists = ...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## `KMI_ENFORCED`

```python
kernel_build_abi(kmi_enforced = ...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## `GENERATE_VMLINUX_BTF`

```python
kernel_build(generate_vmlinux_btf = ...)
```

See [documentation for all rules].

## `SKIP_MRPROPER`

Not customizable in Bazel.

Reason: 

- For sandbox builds, the `$OUT_DIR` always starts with no contents (as if
  `SKIP_MRPROPER=`).
- For non-sandbox builds, the `$OUT_DIR` is always cached (as if 
  `SKIP_MRPROPER=1`). You may clean its contents with `bazel clean`.

See [sandbox.md](#sandbox.md).

## `SKIP_DEFCONFIG`

Not customizable in Bazel.

Reason: Bazel automatically rebuild `make defconfig` when its relevant sources
change, as if `SKIP_DEFCONFIG` is determined automatically.

## `SKIP_IF_VERSION_MATCHES`

Not customizable in Bazel.

Reason: Incremental builds are supported by default.


## `PRE_DEFCONFIG_CMDS`

Specify in the build config. Or remove from build_config and use 
`kernel_build_config` and `genrule`.

See [documentation for all rules].

See [documentation for `genrule`].

## `POST_DEFCONFIG_CMDS`

Specify in the build config. Or remove from build_config and use 
`kernel_build_config` and `genrule`.

See [documentation for all rules].

See [documentation for `genrule`].

## `POST_KERNEL_BUILD_CMDS`

Not customizable in Bazel.

Reason: commands are disallowd in general because of unclear dependency.

You may define a `genrule` target with appropriate inputs (possibly from a 
`kernel_build` macro), then add the target to your `copy_to_dist_dir` macro.

See [documentation for `genrule`].

## `LTO`

```shell
$ bazel build --lto={default,none,thin,full} TARGETS
$ bazel run   --lto={default,none,thin,full} TARGETS
```

See [disable LTO during development](impl.md#disable-lto-during-development).

## `TAGS_CONFIG`

Not supported. Contact [owners](../OWNERS) if you need support for this config.

## `IN_KERNEL_MODULES`

Not customizable in Bazel.

Reason: This is set by default in `build.config.common`. Its value cannot be
changed.

## `SKIP_EXT_MODULES`

Not customizable in Bazel.

Reason: You may skip building external modules by leaving them out in the
`bazel build` command.

## `DO_NOT_STRIP_MODULES`

Specify in the build config.

## `EXTRA_CMDS`

Not customizable in Bazel.

Reason: commands are disallowd in general because of unclear dependency.

You may define a `genrule` target with appropriate inputs, then add the target
to your `copy_to_dist_dir` macro.

See [documentation for `genrule`].

## `DIST_CMDS`

Not customizable in Bazel.

Reason: commands are disallowd in general because of unclear dependency.

You may define a `genrule` target with appropriate inputs, then add the target
to your `copy_to_dist_dir` macro.

See [documentation for `genrule`].

## `SKIP_CP_KERNEL_HDR`

Not customizable in Bazel.

Reason: You may skip building headers by leaving them out in the
`bazel build` command.

## `BUILD_BOOT_IMG`

```python
kernel_images(build_boot = ...)
```

See [documentation for all rules].

## `BUILD_VENDOR_BOOT_IMG`

```python
kernel_images(build_vendor_boot = ...)
```

**Note**: In `build.sh`, `BUILD_BOOT_IMG` and `BUILD_VENDOR_BOOT_IMG` are
confusingly the same flag. `vendor_boot` is only built if either
`BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT`
is not set.

In Bazel, the flags are rather straightforward. `build_boot` controls the
`boot` image. `build_vendor_boot` controls the `vendor_boot` image. Setting
`build_vendor_boot = True` requires `build_boot = True`.

See [documentation for all rules].

## `SKIP_VENDOR_BOOT`

```python
kernel_images(build_vendor_boot = ...)
```

See [`BUILD_VENDOR_BOOT_IMG`](#build-vendor-boot-img).

See [documentation for all rules].

## `VENDOR_RAMDISK_CMDS`

Not customizable in Bazel.

Reason: commands are disallowd in general because of unclear dependency.

You may define a `genrule` target with appropriate inputs, then add the target
to your `copy_to_dist_dir` macro.

## `SKIP_UNPACKING_RAMDISK`

Specify in the build config.

## `AVB_SIGN_BOOT_IMG`

Specify in the build config.

## `AVB_BOOT_PARTITION_SIZE`

Specify in the build config.

## `AVB_BOOT_KEY`

Specify in the build config.

## `AVB_BOOT_ALGORITHM`

Specify in the build config.

## `AVB_BOOT_PARTITION_NAME`

Specify in the build config.

## `BUILD_INITRAMFS`

```python
kernel_images(build_initramfs = ...)
```

## `MODULES_OPTIONS`

```python
kernel_images(modules_options = ...)
```

## `MODULES_ORDER`

Not customizable in Bazel.

Reason: The Bazel build already sets the order of loading modules for you, and 
`build_utils.sh` uses it generate the `modules.load` files already.

## `GKI_MODULES_LIST`

Not customizable in Bazel.

Reason: This is set to a fixed value in the `module_outs` attribute of
`//common:kernel_aarch64`. 

See [documentation for all rules].

## `VENDOR_DLKM_MODULES_LIST`

```python
kernel_images(vendor_dlkm_modules_list = ...)
```

See [documentation for all rules].

## `VENDOR_DLKM_MODULES_BLOCKLIST`

```python
kernel_images(vendor_dlkm_modules_blocklist = ...)
```

See [documentation for all rules].

## `VENDOR_DLKM_PROPS`

```python
kernel_images(vendor_dlkm_props = ...)
```

See [documentation for all rules].

## `LZ4_RAMDISK`

Specify in the build config.

## `LZ4_RAMDISK_COMPRESS_ARGS`

Specify in the build config.

## `TRIM_NONLISTED_KMI`

```python
kernel_build(trim_nonlisted_kmi = ...)
kernel_build_abi(trim_nonlisted_kmi = ...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## `KMI_SYMBOL_LIST_STRICT_MODE`

```python
kernel_build(kmi_symbol_list_strict_mode = ...)
kernel_build_abi(kmi_symbol_list_strict_mode = ...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## `KMI_STRICT_MODE_OBJECTS`

Not customizable in Bazel.

Reason: for a `kernel_build_abi` macro invocation, this is always
`vmlinux` (regardless of whether it is in `outs`),
plus the list of `module_outs`.

See [documentation for all rules].

See [documentation for ABI monitoring].

## `GKI_DIST_DIR`

Not customizable in Bazel.

Reason: mixed builds are supported by

```python
kernel_build(base_build = ...)
```

See [documentation for implementing Kleaf].

## `GKI_BUILD_CONFIG`

Not customizable in Bazel.

Reason: mixed builds are supported by

```python
kernel_build(base_build = ...)
```

See [documentation for implementing Kleaf].

## `GKI_PREBUILTS_DIR`

```python
kernel_filegroup()
```

See [documentation for all rules].

## `BUILD_DTBO_IMG`

```python
kernel_images(build_dtbo = ...)
```

See [documentation for all rules].

[documentation for all rules]: (https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html)
[documentation for `genrule`]: (https://bazel.build/reference/be/general#genrule)
[documentation for ABI monitoring]: (abi.md)
[documentation for implementing Kleaf]: (impl.md)
