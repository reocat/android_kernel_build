def _impl(ctx):
    dec_dir = ctx.actions.declare_directory(ctx.label.name)
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [dec_dir],
        command = """
            echo "Building {name}"
            echo "foo" > {dir}/foo
        """.format(
            name = ctx.label.name,
            dir = dec_dir.path,
        ),
    )
    return DefaultInfo(files = depset([dec_dir]))

mydir = rule(
    implementation = _impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
    },
)

def _file_impl(ctx):
    dec_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [dec_file],
        command = """
            echo "Building {name}"
            touch {dec_file}
        """.format(
            name = ctx.label.name,
            dec_file = dec_file.path,
        ),
    )
    return DefaultInfo(files = depset([dec_file]))

myfile = rule(
    implementation = _file_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
    },
)
