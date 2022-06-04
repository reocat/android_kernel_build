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

# TODO merged into kernel_module
def ddk_module(
        name,
        local_include_dirs = None,
        kernel_include_dirs = None,
        **kwargs):
    """
    Define a DDK (Driver Development Kit) module.

    Args:
      name: Name of target.
      local_include_dirs: A list of include directories in the current package.
      kernel_include_dirs: A list of include directories in the package of the
        `base_kernel` of the `kernel_build`, usually `//common`.

        This requires either the `srcs` of the `kernel_build` also contain
        `srcs` of the `base_kernel`, or `srcs` of this kernel module to
        contain `srcs` of the `base_kernel`.

        FIXME improve docs here
        FIXME improve how GKI headers are included
      kwargs: See [`kernel_module`](#kernel_module) for other arguments.
    """

    kwargs.update(
        name = name,
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_ddk_srcs = native.glob([
            "{}/**/*.h".format(dir) if dir != "." else "**/*.h"
            for dir in local_include_dirs
        ]) if local_include_dirs else None,
    )
    kwargs = kernel_module_set_defaults(kwargs)

    makefiles(
        name = "{name}_makefiles".format(name = name),
        module_srcs = kwargs.get("srcs"),
        module_outs = kwargs.get("outs"),
        local_include_dirs = local_include_dirs,
        kernel_include_dirs = kernel_include_dirs,
    )

    kernel_module(**kwargs)
