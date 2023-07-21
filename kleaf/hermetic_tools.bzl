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
"""
Provide tools for a hermetic build.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//build/kernel/kleaf/impl:hermetic_exec.bzl",
    _hermetic_exec = "hermetic_exec",
    _hermetic_exec_test = "hermetic_exec_test",
)
load("//build/kernel/kleaf/impl:hermetic_genrule.bzl", _hermetic_genrule = "hermetic_genrule")
load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", _hermetic_toolchain = "hermetic_toolchain")

# Re-export functions
hermetic_exec = _hermetic_exec
hermetic_exec_test = _hermetic_exec_test
hermetic_genrule = _hermetic_genrule
hermetic_toolchain = _hermetic_toolchain

_PY_TOOLCHAIN_TYPE = "@bazel_tools//tools/python:toolchain_type"

# Deprecated.
HermeticToolsInfo = provider(
    doc = """Legacy information provided by [hermetic_tools](#hermetic_tools).

Deprecated:
    Use `hermetic_toolchain` instead. See `build/kernel/kleaf/docs/hermeticity.md`.
""",
    fields = {
        "deps": "A list containing the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
        # TODO(b/250646733): Delete this field
        "additional_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

Alternative setup script that preserves original `PATH`.

After using this script, the shell environment prioritizes using hermetic tools, but falls
back on tools from the original `PATH` if a tool cannot be found.

Use with caution. Using this script does not provide hermeticity. Consider using `setup` instead.
""",
        "run_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

setup script to initialize the environment to only use the hermetic tools in
[execution phase](https://docs.bazel.build/versions/main/skylark/concepts.html#evaluation-model),
e.g. for generated executables and tests""",
        "run_additional_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

Like `run_setup` but preserves original `PATH`.""",
    },
)

_HermeticToolchainInfo = provider(
    doc = "Toolchain information provided by [hermetic_tools](#hermetic_tools).",
    fields = {
        "deps": "a depset containing the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
        "run_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

setup script to initialize the environment to only use the hermetic tools in
[execution phase](https://docs.bazel.build/versions/main/skylark/concepts.html#evaluation-model),
e.g. for generated executables and tests""",
        "run_additional_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

Like `run_setup` but preserves original `PATH`.""",
    },
)

def _handle_python(ctx, py_outs, runtime):
    if not py_outs:
        return struct(
            hermetic_outs_dict = {},
            info_deps = [],
        )

    hermetic_outs_dict = {}
    for tool_name in py_outs:
        out = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, tool_name))
        hermetic_outs_dict[tool_name] = out
        ctx.actions.symlink(
            output = out,
            target_file = runtime.interpreter,
            is_executable = True,
            progress_message = "Creating symlink for {}: {}".format(
                paths.basename(out.path),
                ctx.label,
            ),
        )
    return struct(
        hermetic_outs_dict = hermetic_outs_dict,
        # TODO(b/247624301): Use depset in HermeticToolsInfo.
        info_deps = runtime.files.to_list(),
    )

# TODO(b/291816237): Deprecate tar_args
def _handle_tar(ctx, src, out, hermetic_base, deps):
    command = """
        set -e
        PATH={hermetic_base}
        (
            toybox=$(realpath {src})
            if [[ $(basename $toybox) != "toybox" ]]; then
                echo "Expects toybox for tar" >&2
                exit 1
            fi

            cat > {out} << EOF
#!/bin/sh

$toybox tar "\\$@" {tar_args}
EOF
        )
    """.format(
        src = src.path,
        out = out.path,
        hermetic_base = hermetic_base,
        tar_args = " ".join([shell.quote(arg) for arg in ctx.attr.tar_args]),
    )

    ctx.actions.run_shell(
        inputs = deps + [src],
        outputs = [out],
        command = command,
        mnemonic = "HermeticToolsTar",
        progress_message = "Creating wrapper for tar: {}".format(ctx.label),
    )

def _handle_rsync(ctx, out, hermetic_base, deps):
    if not ctx.attr.rsync_args:
        return

    command = """
        set -e
        export PATH
        rsync=$(realpath $({hermetic_base}/which rsync))
        cat > {out} << EOF
#!/bin/sh

$rsync "\\$@" {rsync_args}
EOF
    """.format(
        out = out.path,
        hermetic_base = hermetic_base,
        rsync_args = " ".join([shell.quote(arg) for arg in ctx.attr.rsync_args]),
    )

    ctx.actions.run_shell(
        inputs = deps,
        outputs = [out],
        command = command,
        mnemonic = "HermeticToolsRsync",
        progress_message = "Creating wrapper for rsync: {}".format(ctx.label),
    )

def _get_single_file(ctx, target):
    files_list = target.files.to_list()
    if len(files_list) != 1:
        fail("{}: {} does not contain a single file".format(
            ctx.label,
            target.label,
        ))
    return files_list[0]

def _handle_hermetic_symlinks(ctx):
    hermetic_symlinks_dict = {}
    for actual_target, tool_names in ctx.attr.symlinks.items():
        for tool_name in tool_names.split(":"):

            # TODO(b/291816237): Deprecate tar_args
            if tool_name == "tar" and ctx.attr.tar_args:
                tool_name = "kleaf_internal_do_not_use_real_tar"

            out = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, tool_name))
            target_file = _get_single_file(ctx, actual_target)
            ctx.actions.symlink(
                output = out,
                target_file = target_file,
                is_executable = True,
                progress_message = "Creating symlinks to in-tree tools {}/{}".format(
                    ctx.label,
                    tool_name,
                ),
            )
            hermetic_symlinks_dict[tool_name] = out

    # TODO(b/291816237): Deprecate tar_args
    if "kleaf_internal_do_not_use_real_tar" in hermetic_symlinks_dict:
        tar_out = ctx.actions.declare_file("{}/tar".format(ctx.attr.name))
        _handle_tar(
            ctx = ctx,
            src = hermetic_symlinks_dict["kleaf_internal_do_not_use_real_tar"],
            out = tar_out,
            hermetic_base = hermetic_symlinks_dict.values()[0].dirname,
            deps = hermetic_symlinks_dict.values(),
        )
        hermetic_symlinks_dict["tar"] = tar_out

    return hermetic_symlinks_dict

def _handle_host_tools(ctx, hermetic_base, deps):
    deps = list(deps)
    host_outs = []
    rsync_out = None
    for host_tool in ctx.attr.host_tools:
        f = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, host_tool))
        if host_tool == "rsync":
            rsync_out = f
        else:
            host_outs.append(f)

    command = """
            set -e
          # export PATH so which can work
            export PATH
            for i in {host_outs}; do
                {hermetic_base}/ln -s $({hermetic_base}/which $({hermetic_base}/basename $i)) $i
            done
        """.format(
        host_outs = " ".join([f.path for f in host_outs]),
        hermetic_base = hermetic_base,
    )

    ctx.actions.run_shell(
        inputs = deps,
        outputs = host_outs,
        command = command,
        progress_message = "Creating symlinks to {}".format(ctx.label),
        mnemonic = "HermeticTools",
        execution_requirements = {
            "no-remote": "1",
        },
    )

    if rsync_out:
        _handle_rsync(
            ctx = ctx,
            out = rsync_out,
            hermetic_base = hermetic_base,
            deps = deps,
        )
        host_outs.append(rsync_out)

    return host_outs

def _hermetic_tools_impl(ctx):
    deps = [] + ctx.files.deps
    all_outputs = []

    hermetic_outs_dict = _handle_hermetic_symlinks(ctx)

    py3 = _handle_python(
        ctx = ctx,
        py_outs = ctx.attr.py3_outs,
        runtime = ctx.toolchains[_PY_TOOLCHAIN_TYPE].py3_runtime,
    )
    hermetic_outs_dict.update(py3.hermetic_outs_dict)

    hermetic_outs = hermetic_outs_dict.values()
    all_outputs += hermetic_outs
    deps += hermetic_outs

    host_outs = _handle_host_tools(
        ctx = ctx,
        hermetic_base = hermetic_outs[0].dirname,
        deps = deps,
    )

    all_outputs += host_outs

    info_deps = deps + host_outs
    info_deps += py3.info_deps

    fail_hard = """
         # error on failures
           set -e
           set -o pipefail
    """

    setup = fail_hard + """
                export PATH=$({path}/readlink -m {path})
                # Ensure _setup_env.sh keeps the original items in PATH
                export KLEAF_INTERNAL_BUILDTOOLS_PREBUILT_BIN={path}
""".format(path = all_outputs[0].dirname)
    additional_setup = """
                export PATH=$({path}/readlink -m {path}):$PATH
""".format(path = all_outputs[0].dirname)
    run_setup = fail_hard + """
                export PATH=$({path}/readlink -m {path})
""".format(path = paths.dirname(all_outputs[0].short_path))
    run_additional_setup = fail_hard + """
                export PATH=$({path}/readlink -m {path}):$PATH
""".format(path = paths.dirname(all_outputs[0].short_path))

    hermetic_toolchain_info = _HermeticToolchainInfo(
        deps = depset(info_deps),
        setup = setup,
        run_setup = run_setup,
        run_additional_setup = run_additional_setup,
    )

    default_info_files = [
        file
        for file in all_outputs
        if not file.basename.startswith("kleaf_internal_do_not_use")
    ]

    infos = [
        DefaultInfo(files = depset(default_info_files)),
        platform_common.ToolchainInfo(
            hermetic_toolchain_info = hermetic_toolchain_info,
        ),
        OutputGroupInfo(
            **{file.basename: depset([file]) for file in all_outputs}
        ),
    ]

    if not ctx.attr._disable_hermetic_tools_info[BuildSettingInfo].value:
        hermetic_tools_info = HermeticToolsInfo(
            deps = info_deps,
            setup = setup,
            additional_setup = additional_setup,
            run_setup = run_setup,
            run_additional_setup = run_additional_setup,
        )
        infos.append(hermetic_tools_info)

    return infos

_hermetic_tools = rule(
    implementation = _hermetic_tools_impl,
    doc = "",
    attrs = {
        "host_tools": attr.string_list(),
        "py3_outs": attr.string_list(),
        "deps": attr.label_list(doc = "Additional_deps", allow_files = True),
        "tar_args": attr.string_list(),
        "symlinks": attr.label_keyed_string_dict(
            doc = "symlinks to labels",
            allow_files = True,
        ),
        "_disable_hermetic_tools_info": attr.label(
            default = "//build/kernel/kleaf/impl:incompatible_disable_hermetic_tools_info",
        ),
        "rsync_args": attr.string_list(),
    },
    toolchains = [
        config_common.toolchain_type(_PY_TOOLCHAIN_TYPE, mandatory = True),
    ],
)

def hermetic_tools(
        name,
        srcs,
        host_tools = None,
        deps = None,
        tar_args = None,
        rsync_args = None,
        py3_outs = None,
        symlinks = None,
        aliases = None,
        **kwargs):
    """Provide tools for a hermetic build.

    Args:
        name: Name of the target.
        srcs: A list of labels referring to tools for hermetic builds. This is usually a `glob()`.

          Each item in `{srcs}` is treated as an executable that are added to the `PATH`.
        symlinks: A dictionary, where keys are labels to an executable, and
          values are names to the tool, separated with `:`. e.g.

          ```
          {"//label/to:toybox": "cp:realpath"}
          ```
        host_tools: An allowlist of names of tools that are allowed to be used from the host.

          For each token `{tool}`, the label `{name}/{tool}` is created to refer to the tool.
        py3_outs: List of tool names that are resolved to Python 3 binary.
        deps: additional dependencies. Unlike `srcs`, these aren't added to the `PATH`.
        tar_args: List of fixed arguments provided to `tar` commands.
        rsync_args: List of fixed arguments provided to `rsync` commands.
        aliases: [nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).

          List of aliases to create to refer to a single tool.

          For example, if `aliases = ["cp"],` then `<name>/cp` refers to a
          `cp`.

          **Note**: It is not recommended to rely on these targets. Consider
          using the full hermetic toolchain with
          [`hermetic_toolchain`](#hermetic_toolchainget) or
          [`hermetic_genrule`](#hermetic_genrule), etc.

          **Note**: Items in `srcs`, `host_tools` and `py3_outs` already have
          `<name>/<tool>` target created.
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common
    """

    if aliases == None:
        aliases = []

    if symlinks == None:
        symlinks = {}

    if host_tools:
        aliases += host_tools

    if srcs:
        aliases += [
            paths.basename(native.package_relative_label(src).name)
            for src in srcs
        ]
        symlinks = symlinks | {
            src: paths.basename(native.package_relative_label(src).name)
            for src in srcs
        }

    if py3_outs:
        aliases += py3_outs

    _hermetic_tools(
        name = name,
        host_tools = host_tools,
        py3_outs = py3_outs,
        deps = deps,
        tar_args = tar_args,
        rsync_args = rsync_args,
        symlinks = symlinks,
        **kwargs
    )

    for alias in aliases:
        native.filegroup(
            name = name + "/" + alias,
            srcs = [name],
            output_group = alias,
            # Mark aliases as deprecated to discourage direct usage.
            deprecation = "Use hermetic_toolchain or hermetic_genrule for the full hermetic toolchain",
            tags = ["manual"],
        )
