load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _transition_impl(settings, attr):
    prevalue = settings["//build/kernel/kleaf/exp:trim_real_value"]
    rule_value = attr.trim

    trim_real_value = None
    if prevalue == "unset":
        trim_real_value = "true" if rule_value else "false"
    else:
        trim_real_value = prevalue

    return {
        "//build/kernel/kleaf/exp:trim_real_value": trim_real_value,
    }

_myrule_transition = transition(
    implementation = _transition_impl,
    inputs = [
        "//build/kernel/kleaf/exp:trim_real_value",
    ],
    outputs = [
        "//build/kernel/kleaf/exp:trim_real_value",
    ],
)

def _myrule_impl(ctx):
    actual_trim = ctx.attr._actual_trim[BuildSettingInfo].value
    if actual_trim == "unset":
        fail("I don't know whether to trim or not")
    f = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.run_shell(
        inputs = [],
        outputs = [f],
        command = """
            sleep 5
            echo trim={trim} > {out}
        """.format(
            out = f.path,
            trim = actual_trim,
        ),
        progress_message = "myrule (trim = {trim}): {label}".format(
            trim = actual_trim,
            label = ctx.label,
        ),
    )
    return DefaultInfo(files = depset([f]))

myrule = rule(
    implementation = _myrule_impl,
    cfg = _myrule_transition,
    attrs = {
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
        "trim": attr.bool(),
        "_actual_trim": attr.label(default = "//build/kernel/kleaf/exp:trim_real_value"),
    },
)

def _parent_impl(ctx):
    return DefaultInfo(files = depset(transitive = [t.files for t in ctx.attr.deps]))

myparent_default = rule(
    implementation = _parent_impl,
    attrs = {
        "deps": attr.label_list(),
    },
)

def _myparent_notrim_transition_impl(settings, attr):
    return {"//build/kernel/kleaf/exp:trim_real_value": "false"}

_myparent_notrim_transition = transition(
    implementation = _myparent_notrim_transition_impl,
    inputs = [],
    outputs = [
        "//build/kernel/kleaf/exp:trim_real_value",
    ],
)

myparent_notrim = rule(
    implementation = _parent_impl,
    cfg = _myparent_notrim_transition,
    attrs = {
        "deps": attr.label_list(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def my_outer_macro(name, internal_rule):
    myparent_default(
        name = name + "_parent_default",
        deps = [internal_rule],
    )
    myparent_notrim(
        name = name + "_parent_notrim",
        deps = [internal_rule],
    )
    native.filegroup(
        name = name,
        srcs = [
            name + "_parent_default",
            name + "_parent_notrim",
        ],
    )
