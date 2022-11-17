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

"""Generates Makefile and Kbuild files for a DDK module."""

load(
    ":common_providers.bzl",
    "DdkSubmoduleInfo",
    "ModuleSymversInfo",
)
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo", "get_include_depset")

# Expected infos in deps
_DEP_EXPECT_INFOS = [
    DdkHeadersInfo,
    ModuleSymversInfo,
    DdkSubmoduleInfo,
]

def _handle_copt(ctx):
    # copt values contains prefixing "-", so we must use --copt=-x --copt=-y to avoid confusion.
    # We treat $(location) differently because paths must be relative to the Makefile
    # under {package}, e.g. for -include option.

    expand_targets = []
    expand_targets += ctx.attr.module_srcs
    expand_targets += ctx.attr.module_hdrs
    expand_targets += ctx.attr.module_deps

    copt_content = []
    for copt in ctx.attr.module_copts:
        expanded = ctx.expand_location(copt, targets = expand_targets)

        if copt != expanded:
            if not copt.startswith("$(") or not copt.endswith(")") or \
               copt.count("$(") > 1:
                # This may be an item like "-include=$(location X)", which is
                # not allowed. "$(location X) $(location Y)" is also not allowed.
                # The predicate here may not be accurate, but it is a good heuristic.
                fail(
                    """{}: {} is not allowed. An $(location) expression must be its own item.
                       For example, Instead of specifying "-include=$(location X)",
                       specify two items ["-include", "$(location X)"] instead.""",
                    ctx.label,
                    copt,
                )

        copt_content.append({
            "expanded": expanded,
            "is_path": copt != expanded,
        })
    out = ctx.actions.declare_file("{}/copts.json".format(ctx.attr.name))
    ctx.actions.write(
        output = out,
        content = json.encode_indent(copt_content, indent = "  "),
    )
    return out

def _check_no_ddk_headers_in_srcs(ctx, module_label):
    for target in ctx.attr.module_srcs:
        if DdkHeadersInfo in target:
            fail(("{}: {} is a ddk_headers or ddk_module but specified in srcs. " +
                  "Specify it in deps instead.").format(
                module_label,
                target.label,
            ))

def _check_empty_with_submodules(ctx, module_label, kernel_module_deps):
    """Checks that, if the outer target contains submodules, it should be empty.

    That is, the top level `ddk_module` should not declare any inputs, outputs or copts; they
    should all be declared in individual `ddk_submodule`'s.
    """

    if kernel_module_deps:
        fail("{}: with submodules, deps on other kernel modules should be specified in individual ddk_submodule: {}".format(
            module_label,
            [dep.label for dep in kernel_module_deps],
        ))

    if not ctx.attr.top_level_makefile:
        fail("{}: with submodules, top_level_makefile must be set. " +
             "(Did you specify another ddk_submodule in the deps?)")

    for attr_name in (
        "srcs",
        "out",
        "hdrs",
        "includes",
        "local_defines",
        "copts",
    ):
        attr_val = getattr(ctx.attr, "module_" + attr_name)
        if attr_val:
            fail("{}: with submodules, {} should be specified in individual ddk_submodule: {}".format(
                module_label,
                attr_name,
                attr_val,
            ))

def _check_non_empty_without_submodules(ctx, module_label):
    """Checks that, if the outer target does not contain submodules, it should not be empty.

    That is, a `ddk_module` without submodules, or a `ddk_submodule`, should declare outputs.
    """

    if not ctx.attr.module_out:
        fail(("{}: out is not specified. Perhaps add\n" +
              "    out = \"{}.ko\"").format(
            module_label,
            module_label.name,
        ))

def _makefiles_impl(ctx):
    module_label = Label(str(ctx.label).removesuffix("_makefiles"))

    _check_no_ddk_headers_in_srcs(ctx, module_label)

    output_makefiles = ctx.actions.declare_directory("{}/makefiles".format(ctx.attr.name))

    kernel_module_deps = []
    submodule_deps = []
    for dep in ctx.attr.module_deps:
        if ModuleSymversInfo in dep:
            kernel_module_deps.append(dep)
        if DdkSubmoduleInfo in dep:
            submodule_deps.append(dep)
        if all([info not in dep for info in _DEP_EXPECT_INFOS]):
            fail("{}: {} is not a valid item in deps. It does not provide any of {}".format(
                module_label,
                dep.label,
                _DEP_EXPECT_INFOS,
            ))

    if submodule_deps:
        _check_empty_with_submodules(ctx, module_label, kernel_module_deps)
    else:
        _check_non_empty_without_submodules(ctx, module_label)

    include_dirs = get_include_depset(
        module_label,
        ctx.attr.module_deps + ctx.attr.module_hdrs,
        ctx.attr.module_includes,
        "includes",
    )

    linux_include_dirs = get_include_depset(
        module_label,
        ctx.attr.module_deps + ctx.attr.module_hdrs,
        ctx.attr.module_linux_includes,
        "linux_includes",
    )

    args = ctx.actions.args()

    # Though flag_per_line is designed for the absl flags library and
    # gen_makefiles.py uses absl flags library, this outputs the following
    # in the output params file:
    #   --foo=value1 value2
    # ... which is interpreted as --foo="value1 value2" instead of storing
    # individual values. Hence, use multiline so the output becomes:
    #   --foo
    #   value1
    #   value2
    args.set_param_file_format("multiline")
    args.use_param_file("--flagfile=%s")

    args.add_all("--kernel-module-srcs", ctx.files.module_srcs)
    if ctx.attr.module_out:
        args.add("--kernel-module-out", ctx.attr.module_out)
    args.add("--output-makefiles", output_makefiles.path)
    args.add("--package", ctx.label.package)

    if ctx.attr.top_level_makefile:
        args.add("--produce-top-level-makefile")

    args.add_all("--linux-include-dirs", linux_include_dirs, uniquify = True)
    args.add_all("--include-dirs", include_dirs, uniquify = True)

    args.add_all(
        "--module-symvers-list",
        depset(transitive = [
            kernel_module[ModuleSymversInfo].restore_paths
            for kernel_module in kernel_module_deps
        ]),
    )

    args.add_all("--local-defines", ctx.attr.module_local_defines)

    copt_file = _handle_copt(ctx)
    args.add("--copt-file", copt_file)

    submodule_makefiles = depset(transitive = [dep.files for dep in submodule_deps])
    args.add_all("--submodule-makefiles", submodule_makefiles, expand_directories = False)

    ctx.actions.run(
        mnemonic = "DdkMakefiles",
        inputs = [copt_file],
        outputs = [output_makefiles],
        executable = ctx.executable._gen_makefile,
        arguments = [args],
        progress_message = "Generating Makefile {}".format(ctx.label),
    )

    outs_depset_direct = []
    if ctx.attr.module_out:
        outs_depset_direct.append((ctx.attr.module_out, ctx.label))
    outs_depset_transitive = [dep[DdkSubmoduleInfo].outs for dep in submodule_deps]

    return [
        DefaultInfo(files = depset([output_makefiles])),
        DdkSubmoduleInfo(
            outs = depset(outs_depset_direct, transitive = outs_depset_transitive),
        ),
    ]

makefiles = rule(
    implementation = _makefiles_impl,
    doc = "Generate `Makefile` and `Kbuild` files for `ddk_module`",
    attrs = {
        # module_X is the X attribute of the ddk_module. Prefixed with `module_`
        # because they aren't real srcs / hdrs / deps to the makefiles rule.
        "module_srcs": attr.label_list(allow_files = [".c", ".h", ".s", ".rs"]),
        "module_hdrs": attr.label_list(allow_files = [".h"]),
        "module_includes": attr.string_list(),
        "module_linux_includes": attr.string_list(),
        "module_deps": attr.label_list(),
        "module_out": attr.string(),
        "module_local_defines": attr.string_list(),
        "module_copts": attr.string_list(),
        "top_level_makefile": attr.bool(),
        "_gen_makefile": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/gen_makefiles",
            executable = True,
            cfg = "exec",
        ),
    },
)
