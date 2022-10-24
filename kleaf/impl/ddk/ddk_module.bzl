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

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
)
load(":kernel_module.bzl", "kernel_module")
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo", "ddk_headers")
load(":ddk/makefiles.bzl", "makefiles")

def ddk_module(
        name,
        kernel_build,
        srcs,
        deps = None,
        hdrs = None,
        includes = None,
        out = None,
        **kwargs):
    """
    Defines a DDK (Driver Development Kit) module.

    Example:

    ```
    ddk_module(
        name = "my_module",
        srcs = ["my_module.c", "private_header.h"],
        # Exported headers
        hdrs = ["include/my_module_exported.h"],
        includes = ["include"],
    )
    ```

    Note: Local headers should be specified in one of the following ways:

    - In a `ddk_headers` target in the same package, if you need to auto-generate `-I` ccflags.
      In that case, specify the `ddk_headers` target in `deps`.
    - Otherwise, in `srcs` if you don't need the `-I` ccflags.

    Exported headers should be specified in one of the following ways:

    - In a separate `ddk_headers` target in the same package. Then specify the
      target in `hdrs`. This is recommended if there
      are multiple `ddk_module`s depending on a
      [`glob`](https://bazel.build/reference/be/functions#glob) of headers or a large list
      of headers.
    - Using `hdrs` and `includes` of this target.

    `hdrs` and `includes` have the same semantics as [`ddk_headers`](#ddk_headers). That is,
    this target effectively acts as a `ddk_headers` target when specified in the `deps` attribute
    of another `ddk_module`. In other words, the following code snippet:

    ```
    ddk_module(name = "module_A", hdrs = [...], includes = [...], ...)
    ddk_module(name = "module_B", deps = ["module_A"], ...)
    ```

    ... is effectively equivalent to the following:

    ```
    ddk_headers(name = "module_A_hdrs, hdrs = [...], includes = [...], ...)
    ddk_module(name = "module_A", ...)
    ddk_module(name = "module_B", deps = ["module_A", "module_A_hdrs"], ...)
    ```

    **Ordering of `includes`**

    **The best practice is to not have conflicting header names and search paths.**
    But if you do, see below for ordering of include directories to be
    searched for header files.

    A [`ddk_module`](#ddk_module) is compiled with the following order of include directories
    (`-I` options):

    1. `LINUXINCLUDE` (See `common/Makefile`)
    2. All `deps`, in the specified order
       - recursively apply #3 ~ #4 on each target
    3. All `hdrs`, recursively, in the specified order
       - recursively apply #3 ~ #4 on each target
    4. All `includes` of this target, in the specified order

    In other words, except that `LINUXINCLUDE` always has the highest priority,
    this uses the "postorder" of [depset](https://bazel.build/rules/lib/depset).

    "In the specified order" means that order matters within these lists.
    To prevent buildifier from sorting `includes`, use the `# do not sort` magic line.

    To export a target `:x` in `hdrs` before other targets in `deps`
    (that is, if you need #3 before #2), specify `:x` in the `deps`
    list in the position you want. See example below.

    To export an include directory in `includes` that needs to be included
    before other targets in `hdrs` or `deps` (that is, if you need #4 before
    #3 or #2), specify the include directory in a separate `ddk_headers` target,
    then specify this `ddk_headers` target in `hdrs` and/or `deps` based on
    your needs.

    For example:

    ```
    ddk_headers(name = "dep_a", includes = ["dep_a"])
    ddk_headers(name = "dep_b", includes = ["dep_b"])
    ddk_headers(name = "dep_c", includes = ["dep_c"], hdrs = ["dep_a"])
    ddk_headers(name = "hdrs_a", includes = ["hdrs_a"])
    ddk_headers(name = "hdrs_b", includes = ["hdrs_b"])
    ddk_headers(name = "x", includes = ["x"])

    ddk_module(
        name = "module",
        deps = [":dep_b", ":x", ":dep_c"],
        hdrs = [":hdrs_a", ":x", ":hdrs_b"],
        includes = ["self_1", "self_2"],
    )
    ```

    Then `":module"` is compiled with these flags, in this order:

    ```
    # 1.
    $(LINUXINCLUDE)

    # 2. deps, recursively
    -Idep_b
    -Ix
    -Idep_a   # :dep_c depends on :dep_a, so include dep_a/ first
    -Idep_c

    # 3. hdrs
    -Ihdrs_a
    # x is already included, skip
    -Ihdrs_b

    # 4. includes
    -Iself_1
    -Iself_2
    ```

    A dependent module automatically gets #3 and #4, in this order. For example:

    ```
    ddk_module(
        name = "child",
        deps = [":module"],
        # ...
    )
    ```

    Then `":child"` is compiled with these flags, in this order:

    ```
    # 1.
    $(LINUXINCLUDE)

    # 2. deps, recursively
    -Ihdrs_a
    -Ix
    -Ihdrs_b
    -Iself_1
    -Iself_2
    ```

    Args:
        name: Name of target. This should usually be name of the output `.ko` file without the
          suffix.
        srcs: sources and local headers.
        deps: A list of dependent targets. Each of them must be one of the following:

            - [`kernel_module`](#kernel_module)
            - [`ddk_module`](#ddk_module)
            - [`ddk_headers`](#ddk_headers).
        hdrs: See [`ddk_headers.hdrs`](#ddk_headers-hdrs)
        includes: See [`ddk_headers.includes`](#ddk_headers-includes)
        kernel_build: [`kernel_build`](#kernel_build)
        out: The output module file. By default, this is `"{name}.ko"`.
        kwargs: Additional attributes to the internal rule.
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if out == None:
        out = "{}.ko".format(name)

    kernel_module(
        name = name,
        kernel_build = kernel_build,
        srcs = srcs,
        deps = deps,
        outs = [out],
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_module_symvers_name = "{name}_Module.symvers".format(name = name),
        internal_drop_modules_order = True,
        internal_exclude_kernel_build_module_srcs = True,
        internal_hdrs = hdrs,
        internal_includes = includes,
        **kwargs
    )

    private_kwargs = dict(kwargs)
    private_kwargs["visibility"] = ["//visibility:private"]

    makefiles(
        name = name + "_makefiles",
        module_srcs = srcs,
        module_hdrs = hdrs,
        module_includes = includes,
        module_out = out,
        module_deps = deps,
        **private_kwargs
    )
