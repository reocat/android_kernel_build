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

load(":ddk/makefile.bzl", "makefile")
load(":kernel_module.bzl", "kernel_module", "kernel_module_set_defaults")

# TODO merged into kernel_module
def ddk_module(
        name,
        include_dirs = None,
        **kwargs):
    """
    Define a DDK (Driver Development Kit) module.

    Args:
      name: Name of target.
      include_dirs: A list of include directories in the current package.
      kwargs: See [`kernel_module`](#kernel_module) for other arguments.
    """

    if kwargs.get("makefile"):
        fail("//{}:{}: makefile is not a valid attribute of ddk_module".format(native.package(), name))

    kwargs.update(
        name = name,
    )
    kwargs = kernel_module_set_defaults(kwargs, exclude_makefiles = True)

    makefile(
        name = "{name}_makefile".format(name = name),
        module_srcs = kwargs.get("srcs"),
        module_outs = kwargs.get("outs"),
        kernel_build = kwargs.get("kernel_build"),
        include_dirs = include_dirs,
    )
    kwargs["makefile"] = [":{name}_makefile".format(name = name)]
    kwargs["srcs"] += native.glob(["{}/**/*.h".format(dir) for dir in include_dirs])

    kernel_module(**kwargs)
