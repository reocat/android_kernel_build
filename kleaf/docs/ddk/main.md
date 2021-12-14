# Driver Development Kit (DDK)

## Table of Contents

[Objective](#objective)

[Benefits of using DDK](#benefits-of-using-ddk)

[Defining a collection of DDK headers](#ddk_headers)

[Developing a DDK module](#ddk_module)

[Using headers from the common kernel](common_headers.md)

[Resolving common errors](errors.md)

## Objective

The Driver Development Kit (DDK) shall provide an easy way to develop Kernel
modules for GKI kernels. It should be suitable for new modules as well as for
existing modules and regardless of their location within the source tree.

## Benefits of using DDK

* Support kernel module definitions for GKI kernels, possibly with reasonable
  migration steps.
* Ensure correct toolchain use (compilers, linkers, flags, etc.)
* Ensure correct visibility of resources provided by the GKI kernels (such as
  headers, Makefiles)
* Simple definition of kernel modules in one-place (avoiding separate definition
  locations)
* Unnecessary boilerplate (such as similarly looking Makefiles) generated during
  the make process.

## Example on the virtual device

For an up-to-date example of how DDK modules are developed on the virtual
devices, see 
[`BUILD.bazel` for virtual devices](https://android.googlesource.com/kernel/common-modules/virtual-device/+/refs/heads/android-mainline/BUILD.bazel)
.

## ddk\_headers

A `ddk_headers` target consists of the following:

- A list of header `.h` files, that `ddk_module`s depending on it can use.
- A list of include directories (`-I` option) that `ddk_module`s depending on it
  can search headers from.

`ddk_headers` can be chained. That is, a `ddk_headers` target may re-export the
header files and include directories of another `ddk_headers` target.

You may define a `ddk_headers` target to include a collection of header files
and include directories to search from. You may want to do this because:

- You have a separate kernel source tree to build the kernel modules that does
  not track
  the [Android Common Kernel (ACK)](https://android.googlesource.com/kernel/common/)
  source tree.
- You want to define one or more sets of exported headers for a DDK module to
  suit the needs of the dependent modules.
- Or any reason unlisted here.

For up-to-date information about `ddk_headers`, its API, and examples, see
[documentation for all rules](../api_reference.md) and click on
the `ddk_headers` rule.

For `ddk_headers` target in the Android Common Kernel source tree, see
[using headers from the common kernel](common_headers.md).

## ddk\_module

A `ddk_module` target is a special external `kernel_module` which `Makefile`
is automatically generated.

A `ddk_module` target may depend on a list of `ddk_headers` target to use the
header files and include directories that the `ddk_headers` target exports.

A `ddk_module` target may re-export header files, include directories, and
`ddk_headers` targets.

A `ddk_module` target may depend on other `ddk_module` targets to use the header
files and include directories that the dependent `ddk_headers` target exports.

For up-to-date information about `ddk_module`, its API, and examples, see
[documentation for all rules](../api_reference.md) and click on the `ddk_module`
rule.

## ddk\_submodule

The `ddk_submodule` rule provides a way to specify multiple module output files
(`*.ko`) within the same `ddk_module`. A `ddk_submoule` describes the inputs and
outputs to build a kernel module without specifying clear kernel module
dependencies. Symbol dependencies are looked up from other `ddk_submodule`
within the same `ddk_module`.

Using `ddk_submodule` is discouraged because of the unclear module dependency.
In addition, one must understand the following caveats before using
`ddk_submodule`:

- Defining `ddk_submodule` alone has virtually no effect. A separate 
  `ddk_module` must be defined to include the `ddk_submodule`.
- Building `ddk_submodule` alone does not build any modules. Build the 
  `ddk_module` instead.
- Incremental builds may be slower than using one `ddk_module` per module 
  (`.ko` output file). If the inputs of a `ddk_submodule` has
  changed, `Kbuild` builds all submodules within the same `ddk_module` with
  no caching.

For up-to-date information about `ddk_module`, its API, examples, and caveats,
see [documentation for all rules](../api_reference.md) and click on the
`ddk_submodule` rule.
