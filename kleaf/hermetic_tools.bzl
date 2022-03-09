HermeticToolsInfo = provider(
    doc = "Information provided by [hermetic_tools](#hermetic_tools).",
    fields = {
        "deps": "the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
        "additional_setup": """Alternative setup script that preserves original PATH.

Use with caution. Using this script does not ensure hermeticity. Consider using `setup` instead.
""",
    },
)

def _impl(ctx):
    deps = [] + ctx.files.srcs + ctx.files.deps
    all_outputs = []

    hermetic_outs = []
    for src in ctx.files.srcs:
        out = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, src.basename))
        hermetic_outs.append(out)
        ctx.actions.symlink(
            output = out,
            target_file = src,
            is_executable = True,
            progress_message = "Creating symlinks to in-tree tools",
        )
    all_outputs += hermetic_outs
    deps += hermetic_outs

    host_outs = ctx.outputs.host_tools
    command = """
        set -e
      # export PATH so which can work
        export PATH
        for i in {host_outs}; do
            {hermetic_base}/ln -s $({hermetic_base}/which $({hermetic_base}/basename $i)) $i
        done
""".format(
        host_outs = " ".join([f.path for f in host_outs]),
        hermetic_base = hermetic_outs[0].dirname,
    )
    ctx.actions.run_shell(
        inputs = deps,
        outputs = ctx.outputs.host_tools,
        command = command,
        progress_message = "Creating symlinks to host tools",
        mnemonic = "HermeticToolsHost",
        execution_requirements = {
            "no-remote": "1",
        },
    )
    all_outputs += ctx.outputs.host_tools
    deps += ctx.outputs.host_tools

    setup = """
                export PATH=$({path}/readlink -m {path})
""".format(path = all_outputs[0].dirname)
    additional_setup = """
                export PATH=$({path}/readlink -m {path}):$PATH
""".format(path = all_outputs[0].dirname)

    return [
        DefaultInfo(files = depset(all_outputs)),
        HermeticToolsInfo(
            deps = deps,
            setup = setup,
            additional_setup = additional_setup,
        ),
    ]

_hermetic_tools = rule(
    implementation = _impl,
    doc = "",
    attrs = {
        "host_tools": attr.output_list(),
        "srcs": attr.label_list(doc = "Hermetic tools in the tree", allow_files = True),
        "deps": attr.label_list(doc = "Additional_deps", allow_files = True),
    },
)

def hermetic_tools(
        name,
        srcs,
        host_tools = None,
        deps = None):
    """Provide tools for a hermetic build.

    Args:
        name: Name of the target.
        srcs: A list of labels referring to tools for hermetic builds. This is usually a `glob()`.

          Each item in `{srcs}` is treated as an executable that are added to the `PATH`.
        host_tools: An allowlist of names of tools that are allowed to be used from the host.

          For each token `{tool}`, the label `{name}/{tool}` is created to refer to the tool.
        deps: additional dependencies. Unlike `srcs`, these aren't added to the `PATH`.
    """

    if host_tools:
        host_tools = ["{}/{}".format(name, tool) for tool in host_tools]

    _hermetic_tools(
        name = name,
        srcs = srcs,
        host_tools = host_tools,
        deps = deps,
    )
