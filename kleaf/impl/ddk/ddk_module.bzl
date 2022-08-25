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
load("//build/kernel/kleaf:directory_with_structure.bzl", dws = "directory_with_structure")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    "//build/kernel/kleaf/artifact_tests:kernel_test.bzl",
    "kernel_module_test",
)
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
    "KernelUnstrippedModulesInfo",
)
load(":ddk/makefiles.bzl", "makefiles")
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo")
load(":debug.bzl", "debug")
load(":kernel_module.bzl", "SIBLING_NAMES", "check_kernel_build")
load(":stamp.bzl", "stamp")
load(":utils.bzl", "utils")

def ddk_module(
        name,
        kernel_build,
        srcs = None,
        hdrs = None,
        deps = None,
        **kwargs):
    """
    Define a DDK (Driver Development Kit) module.

    Args:
      name: Name of target.
    """
    # FIXME docs

    ext_mod = native.package_name()
    internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),

    if srcs == None:
        srcs = [
            "{name}.c".format(name),
        ]

    out_basename = "{}.ko".format(name)

    makefiles(
        name = "{name}_makefiles".format(name = name),
        module_srcs = srcs,
        module_out = out,
        module_hdrs = hdrs,
    )

    main_kwargs = dict(kwargs)
    _ddk_module(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        ext_mod = ext_mod,
        internal_ddk_makefiles_dir = internal_ddk_makefiles_dir,
        out = "{}/{}".format(name, out_basename),
        kernel_build = kernel_build,
        deps = deps,
        **main_kwargs
    )

    kernel_module_test(
        name = name + "_test",
        modules = [name],
    )

    # Define external module for sibling kernel_build's.
    # It may be possible to optimize this to alias some of them with the same
    # kernel_build, but we don't have a way to get this information in
    # the load phase right now.
    for sibling_name in SIBLING_NAMES:
        sibling_kwargs = dict(kwargs)
        sibling_target_name = name + "_" + sibling_name

        # We don't know if {kernel_build}_{sibling_name} exists or not, so
        # add "manual" tag to prevent it from being built by default.
        sibling_kwargs["tags"] = sibling_kwargs.get("tags", []) + ["manual"]

        _ddk_module(
            name = sibling_target_name,
            srcs = srcs,
            hdrs = hdrs,
            ext_mod = ext_mod,
            internal_ddk_makefiles_dir = internal_ddk_makefiles_dir,
            out = "{}/{}".format(sibling_target_name, out_basename),
            # This assumes the target is a kernel_build_abi with define_abi_targets
            # etc., which may not be the case. See below for adding "manual" tag.
            # TODO(b/231647455): clean up dependencies on implementation details.
            kernel_build = kernel_build + "_" + sibling_name,
            deps = None if deps == None else [dep + "_" + sibling_name for dep in deps],
            **sibling_kwargs
        )

def _ddk_module_impl(ctx):
    check_kernel_build(ctx.attr.deps, ctx.attr.kernel_build, ctx.label)

    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.files.hdrs
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_srcs
    inputs += ctx.files.internal_ddk_makefiles_dir
    inputs += [
        ctx.file._search_and_cp_output,
        ctx.file._check_declared_output_list,
    ]
    for dep in ctx.attr.deps:
        inputs += dep[KernelEnvInfo].dependencies

    outdir = ctx.outputs.out.dirname

    # outdir includes target name at the end already. So short_name is the original
    # token in `outs` of `kernel_module` macro.
    # e.g. kernel_module(name = "foo", outs = ["foo.ko"])
    #   => _ddk_module(name = "foo", outs = ["foo/foo.ko"])
    #      ctx.attr.outs = [Label("...:foo/foo.ko")]
    #   => out_basename = "foo.ko"
    prefix = str(ctx.label) + "/"
    if not str(ctx.attr.out).startswith(prefix):
        fail("FATAL: {} does not start with {}".format(ctx.attr.out, prefix))

    # Original `out` attribute of `kernel_module` macro.
    out_basename = str(ctx.attr.out).removeprefix(prefix)

    command = ""
    command += ctx.attr.kernel_build[KernelEnvInfo].setup
    command += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_setup

    for dep in ctx.attr.deps:
        command += dep[KernelEnvInfo].setup

    scmversion_ret = stamp.get_ext_mod_scmversion(ctx)
    inputs += scmversion_ret.deps
    command += scmversion_ret.cmd

    command += """
         # Restore Makefile and Kbuild
           cp -r -l {ddk_makefiles}/* {ext_mod}/
    """.format(
        ddk_makefiles = ctx.file.internal_ddk_makefiles_dir.path,
        ext_mod = ctx.attr.ext_mod,
    )

    # FIXME do not modpost
    # FIXME dedup with kernel_module
    command += """
             # Set variables
               if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
                 module_strip_flag="INSTALL_MOD_STRIP=1"
               fi
               ext_mod_rel=$(rel_path ${{ROOT_DIR}}/{ext_mod} ${{KERNEL_DIR}})
             # Actual kernel module build
               make -C {ext_mod} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}
             # Check if there are remaining *.ko files
               remaining_ko_files=$({check_declared_output_list} \\
                    --declared {out} \\
                    --actual $(cd ${{OUT_DIR}}/${{ext_mod_rel}} && find . -type f -name '*.ko' | sed 's:^[.]/::'))
               if [[ ${{remaining_ko_files}} ]]; then
                 echo "ERROR: The following kernel modules are built but not copied. Add these lines to the outs attribute of {label}:" >&2
                 for ko in ${{remaining_ko_files}}; do
                   echo '    "'"${{ko}}"'",' >&2
                 done
                 echo "Alternatively, install buildozer and execute:" >&2
                 echo "  $ buildozer 'add outs ${{remaining_ko_files}}' {label}" >&2
                 echo "See https://github.com/bazelbuild/buildtools/blob/master/buildozer/README.md for reference" >&2
                 exit 1
               fi

             # Grab outputs
               {search_and_cp_output} --srcdir ${{OUT_DIR}}/${{ext_mod_rel}} --dstdir {outdir} {out}
               """.format(
        label = ctx.label,
        ext_mod = ctx.attr.ext_mod,
        outdir = outdir,
        check_declared_output_list = ctx.file._check_declared_output_list.path,
        out = out_basename,
        search_and_cp_output = ctx.file._search_and_cp_output.path,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "DdkModule",
        inputs = inputs,
        outputs = [ctx.outputs.out],
        command = command,
        progress_message = "Building DDK module {}".format(ctx.label),
    )

    return [
        DefaultInfo(
            files = depset([ctx.outputs.out]),
            # For kernel_module_test
            runfiles = ctx.runfiles(files = [ctx.outputs.out]),
        ),
    ]

_ddk_module = rule(
    implementation = _ddk_module_impl,
    doc = """
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "hdrs": attr.label_list(
            allow_files = True,
        ),
        "internal_ddk_makefiles_dir": attr.label(
            allow_single_file = True,  # A single directory
            doc = "A `makefiles` target that denotes a list of makefiles to restore",
        ),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildExtModuleInfo],
        ),
        "deps": attr.label_list(
            providers = [KernelEnvInfo, KernelModuleInfo],
        ),
        "ext_mod": attr.string(mandatory = True),
        "out": attr.output(),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_check_declared_output_list": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:check_declared_output_list.py"),
        ),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
