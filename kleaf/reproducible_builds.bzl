# Copyright (C) 2021 The Android Open Source Project
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

SourceDateEpochInfo = provider(fields = {
    "dependencies": "dependencies required to restore the value of `SOURCE_DATE_EPOCH`",
    "setup": "setup script to restore the value of `SOURCE_DATE_EPOCH`",
})

def _source_date_epoch_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name)
    if (len(ctx.files.git_dir) == 0):
        # If no .git directory, the `git` command is guaranteed to fail.
        # Like _setup_env.sh, set SOURCE_DATE_EPOCH to empty string.
        command = """
                  echo "" > {out}
        """.format(out = out.path)
    else:
        command = """
                # Like _setup_env.sh, set SOURCE_DATE_EPOCH to empty string if git command fails
                  if [ -z "${{SOURCE_DATE_EPOCH}}" ]; then
                    git -C {git_dir} log -1 --pretty=%ct > {out} || true
                  else
                    echo "${{SOURCE_DATE_EPOCH}}" > {out}
                  fi
        """.format(
            git_dir = ctx.files.git_dir[0].dirname,
            out = out.path,
        )
    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [out],
        progress_message = "Determining timestamp for build",
        use_default_shell_env = True,
        command = command,
        # https://github.com/bazelbuild/bazel/issues/7742: `git` cannot be executed in the sandbox.
        execution_requirements = {
            "no-sandbox": "",
        },
    )
    setup = """
            export SOURCE_DATE_EPOCH=$(cat {out})
    """.format(
        out = out.path,
    )
    return SourceDateEpochInfo(
        dependencies = [out],
        setup = setup,
    )

_source_date_epoch = rule(
    implementation = _source_date_epoch_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "git_dir": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kleaf:debug_print_scripts",
        ),
    },
)

def source_date_epoch(name):
    """Determine the value of `SOURCE_DATE_EPOCH` and store it to a file.

    The rule should be placed in a `BUILD.bazel` file beside the `.git` directory.

    See [explanations of `SOURCE_DATE_EPOCH`](https://reproducible-builds.org/docs/source-date-epoch/).

    Args:
        name: name of the module.
    """
    _source_date_epoch(
        name = name,
        git_dir = native.glob([".git"], exclude_directories = 0),
        srcs = native.glob([".git/**"]),
    )
