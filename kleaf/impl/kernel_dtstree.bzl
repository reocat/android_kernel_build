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

"""Specify a kernel DTS tree."""

visibility("//build/kernel/kleaf/...")

DtstreeInfo = provider("DTS tree info", fields = {
    "srcs": "DTS tree sources",
    "makefile": "DTS tree makefile",
    # Using a list because kernel_env needs to copy files to a directory
    "generated": """list of generated files""",
})

def _kernel_dtstree_impl(ctx):
    return DtstreeInfo(
        srcs = ctx.files.srcs,
        makefile = ctx.file.makefile,
        generated = ctx.files.generated,
    )

_kernel_dtstree = rule(
    implementation = _kernel_dtstree_impl,
    attrs = {
        "srcs": attr.label_list(doc = "kernel device tree sources", allow_files = True),
        "makefile": attr.label(mandatory = True, allow_single_file = True),
        "generated": attr.label_list(allow_files = True),
    },
)

def kernel_dtstree(
        name,
        srcs = None,
        makefile = None,
        generated = None,
        **kwargs):
    """Specify a kernel DTS tree.

    Args:
      name: name of the module
      srcs: sources of the DTS tree. Default is

        ```
        glob(["**"], exclude = [
            "**/.*",
            "**/.*/**",
            "**/BUILD.bazel",
            "**/*.bzl",
        ])
        ```
      makefile: Makefile of the DTS tree. Default is `:Makefile`, i.e. the `Makefile`
        at the root of the package.
      generated: A list of generated files.

        To include these files:
        - Add `DTC_FLAGS += -i $(KLEAF_GENERATED_DTS)` to `Makefile`
        - Use `#include "base_name_of_file.dtsi"` in sources
      **kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    if srcs == None:
        srcs = native.glob(
            ["**"],
            exclude = [
                "**/.*",
                "**/.*/**",
                "**/BUILD.bazel",
                "**/*.bzl",
            ],
        )
    if makefile == None:
        makefile = ":Makefile"

    kwargs.update(
        # This should be the exact list of arguments of kernel_dtstree.
        name = name,
        srcs = srcs,
        makefile = makefile,
        generated = generated,
    )
    _kernel_dtstree(**kwargs)
