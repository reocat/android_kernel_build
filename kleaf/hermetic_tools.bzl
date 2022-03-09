HermeticToolsInfo = provider(
    doc = "Provider that [hermetic_tools](#hermetic_tools) provides",
    fields = {
        "deps": "the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
    },
)

def _impl(ctx):
    deps = [] + ctx.files.srcs
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
    return [
        DefaultInfo(files = depset(all_outputs)),
        HermeticToolsInfo(
            deps = deps,
            setup = setup,
        ),
    ]

_hermetic_tools = rule(
    implementation = _impl,
    doc = "",
    attrs = {
        "host_tools": attr.output_list(),
        "srcs": attr.label_list(doc = "Hermetic tools in the tree", allow_files = True),
    },
)

def hermetic_tools(
        name,
        srcs,
        host_tools):
    """Provide tools for a hermetic build.

    Args:
        name: Name of the target.
        srcs: A list of labels referring to tools for hermetic builds. This is usually a `glob()`.
        host_tools: An allowlist of tools that are allowed to be used from the host.

          For each token `{tool}`, the label `{name}/{tool}` is created to refer to the tool.
    """

    if host_tools:
        host_tools = ["{}/{}".format(name, tool) for tool in host_tools]

    _hermetic_tools(
        name = name,
        srcs = srcs,
        host_tools = host_tools,
    )
