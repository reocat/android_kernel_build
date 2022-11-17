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

"""Rules for defining a DDK (Driver Development Kit) submodule."""

load(":ddk/makefiles.bzl", "makefiles")

def ddk_submodule(
        name,
        srcs,
        out,
        deps = None,
        hdrs = None,
        includes = None,
        local_defines = None,
        copts = None):
    """Declares a DDK (Driver Development Kit) submodule.

    Symbol dependencies between submodules in the same [`ddk_module`](#ddk_module)
    are not specified explicitly. This is convenient when you have multiple module
    files for a subsystem.

    See [Building External Modules](https://www.kernel.org/doc/Documentation/kbuild/modules.rst)
    or `Documentation/kbuild/modules.rst`, section "6.3 Symbols From Another External Module",
    "Use a top-level kbuild file".

    Example:

    ```
    ddk_submodule(
        name = "a",
        out = "a.ko",
        srcs = ["a.c"],
    )

    ddk_submodule(
        name = "b",
        out = "b.ko",
        srcs = ["b_1.c", "b_2.c"],
    )

    ddk_module(
        name = "mymodule",
        kernel_build = ":tuna",
        deps = [":a", ":b"],
    )
    ```

    `linux_includes` must be specified in the top-level `ddk_module`; see
    [ddk_module.linux_includes](#ddk_module-linux_includes).

    **Ordering of `includes`**

    See [ddk_module](#ddk_module).

    Args:
        name: See [ddk_module.name](#ddk_module-name).
        srcs: See [ddk_module.srcs](#ddk_module-srcs).
        out: See [ddk_module.out](#ddk_module-out).
        hdrs: See [ddk_module.hdrs](#ddk_module-hdrs).

            These are only effective in the current submodule, not other submodules declared in the
            same [ddk_module.deps](#ddk_module-deps).

        deps: See [ddk_module.deps](#ddk_module-deps).

            These are only effective in the current submodule, not other submodules declared in the
            same [ddk_module.deps](#ddk_module-deps).

        includes: See [ddk_module.includes](#ddk_module-includes).

            These are only effective in the current submodule, not other submodules declared in the
            same [ddk_module.deps](#ddk_module-deps).

        local_defines: See [ddk_module.local_defines](#ddk_module-local_defines).

            These are only effective in the current submodule, not other submodules declared in the
            same [ddk_module.deps](#ddk_module-deps).

        copts: See [ddk_module.copts](#ddk_module-copts).

            These are only effective in the current submodule, not other submodules declared in the
            same [ddk_module.deps](#ddk_module-deps).
    """

    makefiles(
        name = name,
        module_srcs = srcs,
        module_hdrs = hdrs,
        module_includes = includes,
        module_out = out,
        module_deps = deps,
        module_local_defines = local_defines,
        module_copts = copts,
        top_level_makefile = False,
    )
