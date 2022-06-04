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
# TODO export headers
def ddk_module(
        name,
        hdrs = None,
        **kwargs):
    """
    Define a DDK (Driver Development Kit) module.

    Args:
      name: Name of target.
      kwargs: See [`kernel_module`](#kernel_module) for other arguments.
    """

    kwargs.update(
        name = name,
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_ddk_srcs = hdrs,
    )
    kwargs = kernel_module_set_defaults(kwargs)

    if kwargs.get("outs") != ["{}.ko".format(name)]:
        fail("""//{package}:{name}: ddk_module must have exactly one item in outs, ["{name}.ko"]""".format(
            package = native.package(),
            name = name,
        ))

    makefiles(
        name = "{name}_makefiles".format(name = name),
        module_srcs = kwargs.get("srcs"),
        module_out = kwargs.get("outs")[0],
        module_hdrs = hdrs,
    )

    kernel_module(**kwargs)
