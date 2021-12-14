# Driver Development Kit (DDK)

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

## Table of Contents

[Basic concepts](#concepts)

[Using headers from the common kernel](common_headers.md)

[Defining a collection of DDK headers](headers.md)

[Developing a DDK module](module.md)

[Resolving common errors](errors.md)

## Concepts

### `ddk_headers`

A `ddk_headers` target consists of the following:

- A list of header `.h` files, that `ddk_module`s depending on it can use.
- A list of include directories (`-I` option) that `ddk_module`s depending on it
  can search headers from.

`ddk_headers` can be chained. That is, a `ddk_headers` target may re-export
the header files and include directories of another `ddk_headers` target.

For up-to-date information about `ddk_headers`, its API, and examples, see
[documentation for all rules] and click on the `ddk_headers` rule.

### `ddk_module`

A `ddk_module` target is a special external `kernel_module` which `Makefile`
is automatically generated.

A `ddk_module` target may depend on a list of `ddk_headers` target to use the
header files and include directories that the `ddk_headers` target exports.

A `ddk_module` target may re-export header files, include directories, and
`ddk_headers` targets.

A `ddk_module` target may depend on other `ddk_module` targets to use the header
files and include directories that the dependent `ddk_headers` target exports.

For up-to-date information about `ddk_module`, its API, and examples, see
[documentation for all rules] and click on the `ddk_module` rule.

[documentation for all rules]: https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html
