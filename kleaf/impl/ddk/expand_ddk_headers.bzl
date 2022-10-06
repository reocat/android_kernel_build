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

load(":ddk/ddk_headers.bzl", "DdkHeadersInfo")

_HdrsInfo = provider(fields = {
    "hdrs": "A depset of Target of the `hdrs` attribute",
})

def _hdrs_aspect_impl(target, ctx):
    transitive = []
    for target in ctx.rule.attr.hdrs:
        if _HdrsInfo in target:
            transitive.append(target[_HdrsInfo].hdrs)

    return _HdrsInfo(hdrs = depset(ctx.rule.attr.hdrs, transitive = transitive))

_hdrs_aspect = aspect(
    implementation = _hdrs_aspect_impl,
    doc = "An aspect exploring the `hdrs` attribute",
    attr_aspects = ["hdrs"],
)

def _expand_ddk_headers_impl(ctx):
    all_deps = depset(ctx.attr.deps, transitive = [t[_HdrsInfo].hdrs for t in ctx.attr.deps])
    out_json = {}
    for target in all_deps.to_list():
        if DdkHeadersInfo not in target:
            # Ignore files
            continue
        includes = sorted(target[DdkHeadersInfo].includes.to_list())
        files = target[DdkHeadersInfo].files.to_list()
        file_paths = sorted([file.short_path for file in files])

        out_json[str(target.label)] = {
            "includes": includes,
            "files": file_paths,
        }

    out = ctx.actions.declare_file("{}.json".format(ctx.label.name))
    ctx.actions.write(
        output = out,
        content = json.encode_indent(out_json, indent = "    "),
    )

    return DefaultInfo(files = depset([out]))

expand_ddk_headers = rule(
    implementation = _expand_ddk_headers_impl,
    doc = """Expands [`ddk_headers`](#ddk_headers) definitions to JSON format.

This target goes down to the dependant targets of a list of
[`ddk_headers`](#ddk_headers) targets. For all targets and dependant targets,
expand the definition so that the resulting definition is equivalent to
the original one, but without any dependency to other
[`ddk_headers`](#ddk_headers) targets.
    """,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of [`ddk_headers`](#ddk_headers) targets.",
            aspects = [_hdrs_aspect],
        ),
    },
)
