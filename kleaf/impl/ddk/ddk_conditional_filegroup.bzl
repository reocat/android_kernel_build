load(":utils.bzl", "utils")

DdkConditionalFilegroupInfo = provider(
    fields = {
        "config": "ddk_conditional_filegroup.config",
        "value": "ddk_conditional_filegroup.value",
    },
)

def _ddk_conditional_filegroup_impl(ctx):
    return [
        DefaultInfo(files = depset(transitive = [target.files for target in ctx.attr.srcs])),
        DdkConditionalFilegroupInfo(
            config = ctx.attr.config,
            value = ctx.attr.value,
        ),
    ]

ddk_conditional_filegroup = rule(
    implementation = _ddk_conditional_filegroup_impl,
    attrs = {
        "config": attr.string(mandatory = True),
        "value": attr.bool(mandatory = True),
        "srcs": attr.label_list(allow_files = [".c", ".h", ".s", ".rs"]),
    },
)
