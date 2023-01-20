load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _transition_impl(settings, attr):
    force_disable = settings["//build/kernel/kleaf/exp:force_disable_trim"]
    rule_value = attr.trim

    trim_real_value = None
    if force_disable:
        trim_real_value = False
    else:
        trim_real_value = rule_value

    return {
        "//build/kernel/kleaf/exp:force_disable_trim": False,
        "//build/kernel/kleaf/exp:trim_real_value": trim_real_value,
    }

_myrule_transition = transition(
    implementation = _transition_impl,
    inputs = [
        "//build/kernel/kleaf/exp:force_disable_trim",
    ],
    outputs = [
        "//build/kernel/kleaf/exp:force_disable_trim",
        "//build/kernel/kleaf/exp:trim_real_value",
    ],
)

def _myrule_impl(ctx):
    is_forcifully_disabled = ctx.attr._is_forcifully_disabled[BuildSettingInfo].value
    actual_trim = ctx.attr._actual_trim[BuildSettingInfo].value
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
        progress_message = "myrule (trim = {trim}, force_disable={force_disable}): {label}".format(
            trim = actual_trim,
            force_disable = is_forcifully_disabled,
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
        "_is_forcifully_disabled": attr.label(default = "//build/kernel/kleaf/exp:force_disable_trim"),
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
    return {"//build/kernel/kleaf/exp:force_disable_trim": True}

_myparent_notrim_transition = transition(
    implementation = _myparent_notrim_transition_impl,
    inputs = [],
    outputs = [
        "//build/kernel/kleaf/exp:force_disable_trim",
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

def my_outer_macro(name):
    myrule(
        name = name + "_internal_rule",
        trim = False,
    )
    myparent_default(
        name = name + "_parent_default",
        deps = [name + "_internal_rule"],
    )
    myparent_notrim(
        name = name + "_parent_notrim",
        deps = [name + "_internal_rule"],
    )
    native.filegroup(
        name = name,
        srcs = [
            name + "_parent_default",
            name + "_parent_notrim",
        ],
    )
