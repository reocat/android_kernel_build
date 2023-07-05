"""Select defconfig fragments"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _defconfig_fragment_string_flag_selector_impl(ctx):
    flag_value = ctx.attr.flag[BuildSettingInfo].value
    flag_value = ctx.attr.transforms.get(flag_value) or flag_value

    files_depsets = []

    for target, expected_value in ctx.attr.files.items():
        if expected_value == flag_value:
            files_depsets.append(target.files)

    return DefaultInfo(files = depset(transitive = files_depsets))

defconfig_fragment_string_flag_selector = rule(
    implementation = _defconfig_fragment_string_flag_selector_impl,
    attrs = {
        "flag": attr.label(
            doc = "`string_flag` / `string_setting`",
            mandatory = True,
            providers = [BuildSettingInfo],
        ),
        "files": attr.label_keyed_string_dict(
            doc = "key: label to files. value: value of flag.",
            allow_files = True,
        ),
        "transforms": attr.string_dict(
            doc = "Apply these transforms on `flag`'s value before using",
        )
    },
)
