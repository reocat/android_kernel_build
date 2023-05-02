def _myrule_impl(ctx):
    print(ctx.attr.filegroup)

myrule = rule(
    attrs = {
        "filegroup": attr.label(
            # strings in attr.label.default is okay
            default = "//:filegroup",
        ),
    },
    implementation = _myrule_impl,
)

def mymacro(name):
    return myrule(
        name = name,
        # strings in macros need to be taken care of
        filegroup = Label("//:filegroup"),
    )
