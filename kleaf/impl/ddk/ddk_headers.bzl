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

load("@bazel_skylib//lib:paths.bzl", "paths")

DdkHeadersInfo = provider(fields = {
    "files": "All header files",
    "exported_include_dirs": "",
})

def _ddk_headers_impl(ctx):
    normalized_dirs = []
    for include_dir in ctx.attr.export_include_dirs:
        normalized_dir = paths.normalize(include_dir)

        # TODO Add analysis test for these failures
        if paths.is_absolute(normalized_dir):
            fail("{}: Absolute dirs not allowed in export_include_dirs: {}".format(ctx.label, include_dir))
        if normalized_dir.startswith("."):
            fail("{}: Invalid export_include_dirs: {}".format(ctx.label, include_dir))

        normalized_dirs.append(normalized_dir)

    files = depset(transitive = [src.files for src in ctx.attr.srcs])

    return [
        # Not using ctx.files.srcs to avoid unnecessarily expanding the depset
        DefaultInfo(files = files),
        DdkHeadersInfo(
            files = files,
            exported_include_dirs = [
                paths.join(ctx.label.package, d)
                for d in normalized_dirs
            ],
        ),
    ]

ddk_headers = rule(
    implementation = _ddk_headers_impl,
    attrs = {
        "srcs": attr.label_list(doc = "Headers.", allow_files = [".h"]),
        "export_include_dirs": attr.string_list(
            doc = """A list of directories, relative to the current package, that are re-exported as include directories.

[`ddk_module`](#ddk_module) with `hdrs` including this target automatically
adds the given include directory in the generated `Kbuild` files.

You still need to add the actual header files to `srcs`.
""",
        ),
    },
)
