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

"""Creates a zip archive from the specified targets."""

def _zip_archive_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.zip_file)

    args = ctx.actions.args()
    args.add("-symlinks=false")
    args.add("-o", out.path)
    args.add_all(
        depset(transitive = [target.files for target in ctx.attr.srcs]),
        before_each = "-f",
    )

    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [out],
        executable = ctx.executable._zipper,
        arguments = [args],
        mnemonic = "Zip",
        progress_message = "Generating %s" % (ctx.attr.zip_file),
    )
    return [DefaultInfo(files = depset([out]))]

zip_archive = rule(
    implementation = _zip_archive_impl,
    doc = "A rule to create a zip archive from specified targets",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = "the targets with outputs to put in the generated archive",
        ),
        "zip_file": attr.string(mandatory = True, doc = "the output file name"),
        "_zipper": attr.label(
            default = "//prebuilts/build-tools:linux-x86/bin/soong_zip",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
