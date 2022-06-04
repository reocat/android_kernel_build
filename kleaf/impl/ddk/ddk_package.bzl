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

load(":ddk/makefiles.bzl", "makefiles")
load(":kernel_module.bzl", "kernel_module", "kernel_module_set_defaults")

# TODO merge into kernel_module?
def ddk_package(
        name,
        kernel_build,  # TODO skip specifying kernel_build in ddk_package
        deps = None,
        **kwargs):
    """
    Executes post actions for [`ddk_module`](#ddk_module)s in the same package.

    This includes `make modules_install`, etc.

    This functions similar to a non-DDK external [`kernel_module`](#kernel_module).

    Args:
        name: name of target. Usually this should be the basename of the package
          so that `bazel build //path/to/package` (which is equivalent to
          `//path/to/package:package`) refers to this target.
        kernel_build: [`kernel_build`](#kernel_build)
        deps: A list of [`ddk_module`](#ddk_module) defined in the same package.
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    # FIXME makefiles can be generated in ddk_module
    makefiles(
        name = "{name}_makefiles".format(name = name),
        deps = deps,
    )

    for disallowed_attr in (
        "srcs",
        "makefile",
        "kernel_module_deps",
        "ext_mod",
        "outs",
        "internal_ddk_makefiles_dir",
        "internal_ddk_module_deps",
    ):
        if disallowed_attr in kwargs:
            fail("//{}:{}: unrecognized attribute {}".format(native.package(), name, disallowed_attr))

    kwargs.update(
        name = name,
        kernel_build = kernel_build,
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_ddk_module_deps = deps,
    )
    kwargs = kernel_module_set_defaults(kwargs)

    kernel_module(**kwargs)
