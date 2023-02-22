def mybuild(
        name,
        trim,
        **kwargs):
    _mybuild(
        name = name,
        trim = select({
            "//build/kernel/kleaf/impl:force_disable_trim_is_true": False,
            "//conditions:default": trim,
        }),
        **kwargs
    )

def _mybuild_impl(ctx):
    print(ctx.label, ctx.attr.trim)

_mybuild = rule(
    implementation = _mybuild_impl,
    attrs = {
        "srcs": attr.label_list(),
        "trim": attr.bool(),
    },
)

def _disable_trim_transition_impl(settings, attr):
    return {
        "//build/kernel/kleaf/impl:force_disable_trim": True,
    }

disable_trim_transition = transition(
    inputs = [],
    outputs = ["//build/kernel/kleaf/impl:force_disable_trim"],
    implementation = _disable_trim_transition_impl,
)

def _mybuild_abi_impl(ctx):
    pass

mybuild_abi = rule(
    implementation = _mybuild_abi_impl,
    attrs = {
        "build": attr.label(
            cfg = disable_trim_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
