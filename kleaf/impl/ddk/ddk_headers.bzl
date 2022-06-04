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
    "exported_include_dirs": "",
})

def _ddk_headers_impl(ctx):
    # TODO verify exported_include_dirs not go elsewhere
    return [
        # Not using ctx.files.srcs to avoid unnecessarily expanding the depset
        DefaultInfo(files = depset(transitive = [src.files for src in ctx.attr.srcs])),
        DdkHeadersInfo(exported_include_dirs = [
            paths.join(ctx.label.package, d)
            for d in ctx.attr.export_include_dirs
        ]),
    ]

ddk_headers = rule(
    implementation = _ddk_headers_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "export_include_dirs": attr.string_list(),
    },
)
