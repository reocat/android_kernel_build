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
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@kleaf_host_tools//:host_tools.bzl", _REGISTERED_HOST_TOOLS = "HOST_TOOLS")
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

    return hermetic_symlinks_dict

# TODO(b/291816237): Require all host tools to be registered.
def _handle_unregistered_host_tools(ctx, hermetic_base, deps):
    if not ctx.attr.unregistered_host_tools:
        return []

    # buildifier: disable=print
    print("""\
WARNING: {} contains host_tools {}. They should be predeclared in
   @kleaf_host_tools. This will become an error in the future.
   Add them to @kleaf_host_tools to prevent the error.
""".format(
        ctx.label,
        repr(ctx.attr.unregistered_host_tools),
    ))

    deps = list(deps)
    host_outs = []
    for host_tool in ctx.attr.unregistered_host_tools:
        f = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, host_tool))
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
        progress_message = "Creating host tool symlinks {}".format(ctx.label),
        mnemonic = "HermeticTools",
        execution_requirements = {
            "no-remote": "1",
        },
    )

    return host_outs

def _hermetic_tools_impl(ctx):
    deps = [] + ctx.files.deps
    all_outputs = []

    hermetic_outs_dict = _handle_hermetic_symlinks(ctx)

    hermetic_outs = hermetic_outs_dict.values()
    all_outputs += hermetic_outs
    deps += hermetic_outs

    host_outs = _handle_unregistered_host_tools(
        ctx = ctx,
        hermetic_base = hermetic_outs[0].dirname,
        deps = deps,
    )

    all_outputs += host_outs

    info_deps = deps + host_outs

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
        if "kleaf_internal_do_not_use" not in file.path
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
        "unregistered_host_tools": attr.string_list(),
        "deps": attr.label_list(doc = "Additional_deps", allow_files = True),
        "symlinks": attr.label_keyed_string_dict(
            doc = "symlinks to labels",
            allow_files = True,
        ),
        "_disable_hermetic_tools_info": attr.label(
            default = "//build/kernel/kleaf/impl:incompatible_disable_hermetic_tools_info",
        ),
    },
)

def hermetic_tools(
        name,
        srcs = None,
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

          This only applies to `tar` in `srcs`.
        rsync_args: List of fixed arguments provided to `rsync` commands.

          This only applies to `rsync` in `host_tools`.
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

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    if aliases == None:
        aliases = []

    if symlinks == None:
        symlinks = {}

    if deps == None:
        deps = []

    unregistered_host_tools = []
    if host_tools:
        aliases += host_tools
        additional_symlinks, unregistered_host_tools = \
            _host_tool_to_symlinks(name, host_tools, rsync_args, **private_kwargs)
        symlinks = symlinks | additional_symlinks

    if srcs:
        aliases += [
            paths.basename(native.package_relative_label(src).name)
            for src in srcs
        ]
        symlinks = symlinks | _src_to_symlinks(name, srcs, tar_args, **private_kwargs)

    if py3_outs:
        aliases += py3_outs
        symlinks = symlinks | {
            Label("//build/kernel/kleaf/impl:python_interpreter"): ":".join(py3_outs),
        }

        # Do not use .append or += to avoid modifying the incoming object,
        # which may be a select
        deps = deps + [Label("//build/kernel/kleaf/impl:python_runtime_files")]

    _hermetic_tools(
        name = name,
        unregistered_host_tools = unregistered_host_tools,
        deps = deps,
        symlinks = symlinks,
        **kwargs
    )

    alias_kwargs = kwargs | dict(
        # Mark aliases as deprecated to discourage direct usage.
        deprecation = "Use hermetic_toolchain or hermetic_genrule for the full hermetic toolchain",
        tags = ["manual"],
    )

    for alias in aliases:
        native.filegroup(
            name = name + "/" + alias,
            srcs = [name],
            output_group = alias,
            **alias_kwargs
        )

def _src_to_symlinks(name, srcs, tar_args, **private_kwargs):
    """Map `hermetic_tools.srcs` to `_hermetic_tools.symlinks`"""
    symlinks = {}
    for src in srcs:
        tool_name = paths.basename(native.package_relative_label(src).name)

        if tar_args and tool_name == "tar":
            symlinks = symlinks | _replace_tar(name, src, tar_args, **private_kwargs)
        else:
            symlinks[src] = tool_name

    return symlinks

# TODO(b/291816237): Deprecate tar_args
def _replace_tar(name, src, tar_args, **private_kwargs):
    """Handle hermetic_tools.tar_args, returning values to `_hermetic_tools.symlinks`."""
    symlinks = {}
    symlinks[src] = "kleaf_internal_do_not_use/tar_toybox"

    write_file(
        name = name + "/kleaf_internal_do_not_use/tar_bin",
        out = name + "/kleaf_internal_do_not_use/tar",
        content = [
            "#!/bin/sh",
            """${{0%/*}}/kleaf_internal_do_not_use/tar_toybox tar "$@" {tar_args}""".format(
                tar_args = " ".join([shell.quote(arg) for arg in tar_args]),
            ),
        ],
        **private_kwargs
    )
    symlinks[name + "/kleaf_internal_do_not_use/tar"] = "tar"

    return symlinks

def _host_tool_to_symlinks(name, host_tools, rsync_args, **private_kwargs):
    """Map `hermetic_tools.host_tools` to `_hermetic_tools.symlinks`"""
    symlinks = {}
    unregistered_host_tools = []
    for host_tool in host_tools:
        if host_tool not in _REGISTERED_HOST_TOOLS:
            unregistered_host_tools.append(host_tool)
            continue
        tool_label = Label("@kleaf_host_tools//:{}".format(host_tool))

        if rsync_args and host_tool == "rsync":
            symlinks = symlinks | _replace_rsync(name, tool_label, rsync_args, **private_kwargs)
        else:
            symlinks[tool_label] = host_tool

    return symlinks, unregistered_host_tools

# TODO(b/291816237): Deprecate rsync_args
def _replace_rsync(name, tool_label, rsync_args, **private_kwargs):
    """Handle hermetic_tools.rsync_args, returnning values to `_hermetic_tools.symlinks`."""
    symlinks = {}
    symlinks[tool_label] = "kleaf_internal_do_not_use/rsync_real"

    write_file(
        name = name + "/kleaf_internal_do_not_use/rsync_bin",
        out = name + "/kleaf_internal_do_not_use/rsync",
        content = [
            "#!/bin/sh -x",
            """${{0%/*}}/kleaf_internal_do_not_use/rsync_real "$@" {rsync_args}""".format(
                rsync_args = " ".join([shell.quote(arg) for arg in rsync_args]),
            ),
        ],
        **private_kwargs
    )
    symlinks[name + "/kleaf_internal_do_not_use/rsync"] = "rsync"

    return symlinks
