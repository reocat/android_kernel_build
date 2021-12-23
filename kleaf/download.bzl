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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _download_filegroup_get_build_number(ctx):
    """
    Return the build number of a `kernel_download_filegroup` rule.
    """
    build_number_flag_value = None
    if ctx.attr.build_number_flag:
        build_number_flag_value = ctx.attr.build_number_flag[BuildSettingInfo].value

    # Use boolean check, not None check, to also guard against empty strings
    if ctx.attr.build_number and build_number_flag_value:
        fail("{}: Only one of `build_number` or `build_number_flag` can be set, but not both.".format(ctx.label))

    if not ctx.attr.build_number and not build_number_flag_value:
        if ctx.attr.build_number_flag:
            fail("""{this_label}:

    One of `build_number` or `build_number_flag` must be set.
    To fix, specify the following in the build command:
        --{flag}=<build_number>
    For example:
        bazel build --{flag}=8027204 {this_label}
""".format(flag = ctx.attr.build_number_flag.label, this_label = ctx.label))
        else:
            fail("""{this_label}:

    One of `build_number` or `build_number_flag` must be set.
    To fix, specify the following in {this_label}:
        build_number=<build_number>
    For example:
        kernel_download_filegroup(
            name = "{this_name}",
            build_number = "8027204",
        )
""".format(this_label = ctx.label, this_name = ctx.label.name))

    if ctx.attr.build_number:
        return ctx.attr.build_number

    return ctx.attr.build_number_flag[BuildSettingInfo].value

def _download_filegroup_impl(ctx):
    build_number = _download_filegroup_get_build_number(ctx)
    outputs = []
    for filename in ctx.attr.files:
        output = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, filename))
        outputs.append(output)
        ctx.actions.run(
            # TODO(b/206079661): Make this hermetic by using python in prebuilts
            executable = ctx.file._download_artifact,
            arguments = [
                "--build_number",
                build_number,
                "--target",
                ctx.attr.target,
                "--out",
                output.dirname,
                "--file",
                filename,
            ],
            outputs = [output],
            progress_message = "Downloading {}/{}/{} {}".format(build_number, ctx.attr.target, filename, ctx.label),
        )

    return DefaultInfo(files = depset(outputs))

download_filegroup = rule(
    implementation = _download_filegroup_impl,
    doc = """Specify a list of downloaded prebuilts.

The list of kernel prebuilts is downloaded from [ci.android.com](http://ci.android.com) at build
time.

This is similar to [`filegroup`](https://docs.bazel.build/versions/main/be/general.html#filegroup)
that gives a convenient name to a collection of targets, which can be referenced from other rules.

If you need `KernelFilesInfo` as well, wrap it in a [`kernel_filegroup`](#kernel_filegroup).
""",
    attrs = {
        "files": attr.string_list(
            doc = "A list of file names to be downloaded. Default is the artifacts of `kernel_aarch64`.",
            mandatory = True,
        ),
        "build_number": attr.string(
            mandatory = False,
            doc = """The build number to download prebuilts from.

One of `build_number` or `build_number_flag` must be set, but not both.
""",
        ),
        "build_number_flag": attr.label(
            mandatory = False,
            providers = [BuildSettingInfo],
            doc = """A build setting that provides the build number to download prebuilts from.

One of `build_number` or `build_number_flag` must be set, but not both.
""",
        ),
        "target": attr.string(
            mandatory = True,
            doc = "Target name to download prebuilts from.",
        ),
        "_download_artifact": attr.label(
            allow_single_file = True,
            default = "//build/kleaf:download_artifact.py",
        ),
    },
)
