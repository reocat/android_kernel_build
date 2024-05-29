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

load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

DtstreeInfo = provider("DTS tree info", fields = {
    "srcs": "DTS tree sources",
    "makefile": "DTS tree makefile",
    "generated_dir": """directory of of generated files""",
})

def _check_duplicated_basename(ctx, file_list):
    files_by_basename = {}
    for file in file_list:
        if file.basename not in files_by_basename:
            files_by_basename[file.basename] = []
        files_by_basename[file.basename].append(file)
    dup_files_by_basename = {}
    for basename, files in files_by_basename.items():
        if len(files) > 1:
            dup_files_by_basename[basename] = files
    if dup_files_by_basename:
        fail("{}: Duplicated file names found in generated: {}".format(ctx.label, dup_files_by_basename))

def _generate_dtstree_dir(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    if not ctx.files.generated:
        return None

    _check_duplicated_basename(ctx, ctx.files.generated)
    gen_dtstree_dir = ctx.actions.declare_directory(ctx.attr.name + "/dtstree")
    gen_dtstree_dir_cmd = hermetic_tools.setup + """
        mkdir -p {out_dir}/generated
        cp -aL -t {out_dir}/generated {dtstree_generated_files}
    """.format(
        out_dir = gen_dtstree_dir.path,
        dtstree_generated_files = " ".join([file.path for file in ctx.files.generated]),
    )
    ctx.actions.run_shell(
        command = gen_dtstree_dir_cmd,
        inputs = ctx.files.generated,
        outputs = [gen_dtstree_dir],
        tools = hermetic_tools.deps,
        mnemonic = "KernelDtstreeGenerate",
        progress_message = "Generating DTS Tree {}".format(ctx.label),
    )
    return gen_dtstree_dir

def _kernel_dtstree_impl(ctx):
    gen_dtstree_dir = _generate_dtstree_dir(ctx)

    return DtstreeInfo(
        srcs = ctx.files.srcs,
        makefile = ctx.file.makefile,
        generated_dir = gen_dtstree_dir,
    )

_kernel_dtstree = rule(
    implementation = _kernel_dtstree_impl,
    attrs = {
        "srcs": attr.label_list(doc = "kernel device tree sources", allow_files = True),
        "makefile": attr.label(mandatory = True, allow_single_file = True),
        "generated": attr.label_list(allow_files = True),
    },
    toolchains = [hermetic_toolchain.type],
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

        To include these files, use `#include "generated/base_name_of_file.dtsi"`
        in files in `srcs`. Only append the base name of the file, not the
        full path, after `generated/`.
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
