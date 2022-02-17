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

load("//build/kernel/kleaf:default_build_configs.bzl", "INTERESTING_BUILD_CONFIG_VARS")

_VAR_QUOTE_BEGIN = "$'"
_VAR_QUOTE_END = "'"
_VAR_ARRAY_BEGIN = "("
_VAR_ARRAY_END = ")"

def _relpath(dst, base, what):
    """Naive algorithm to determine the relative path from base to dst.

    Requires base to be a parent of dst.
    """
    dst = str(dst)
    base = str(base)
    if not base.endswith("/"):
        base += "/"
    if not dst.startswith(base):
        fail("{what}: Cannot calculate relative path from {dst} to {base}".format(
            what = what if what else "<unknown>",
            dst = dst,
            base = base,
        ))
    return dst[len(base):]

def _parse_set_vars(content, what):
    """Naive algorithm to parse the output of `set` to find environment variables."""
    in_fn = False
    ret = {}
    for line in content.splitlines():
        line = line.strip()
        if line == "{":
            in_fn = True
            continue
        elif line == "}":
            in_fn = False
            continue
        if in_fn:
            continue
        if "=" not in line:
            continue
        tup = line.split("=", 1)
        if len(tup) != 2:
            continue
        k, v = tup
        if k not in INTERESTING_BUILD_CONFIG_VARS:
            continue
        if v.startswith(_VAR_ARRAY_BEGIN) and v.endswith(_VAR_ARRAY_END):
            fail("@{}: Unsupported line: {}".format(what, line))
        if v.startswith(_VAR_QUOTE_BEGIN) and v.endswith(_VAR_QUOTE_END):
            v = v[len(_VAR_QUOTE_BEGIN):-len(_VAR_QUOTE_END)]
        ret[k] = v
    return ret

def _get_new_vars(before, after, what):
    """Naive algorithm to parse the output of `set` to find new environment variables."""
    before_vars = _parse_set_vars(before, what)
    after_vars = _parse_set_vars(after, what)
    diff = {k: v for k, v in after_vars.items() if k not in before_vars or before_vars[k] != v}
    for k, default_value in INTERESTING_BUILD_CONFIG_VARS.items():
        if k not in diff:
            diff[k] = default_value
    return diff

def _impl(repository_ctx):
    src = repository_ctx.path(repository_ctx.attr.src)
    root_dir = repository_ctx.attr.root_dir
    kernel_dir = repository_ctx.attr.kernel_dir
    if not kernel_dir:
        kernel_dir = _relpath(src.dirname, root_dir, "@" + repository_ctx.name)

    # Use bash from the environment, just like //build/kernel:host-tools
    bash = str(repository_ctx.which("bash"))

    env = {
        "ROOT_DIR": ".",
        "KERNEL_DIR": kernel_dir,
    }
    tmp = repository_ctx.path("tmp")
    before = tmp.get_child("before")
    after = tmp.get_child("after")
    command = """
        mkdir -p {tmp} &&
        ( set ) > {before} && \
        source {src} && \
        ( set ) > {after}
    """.format(
        src = src,
        comm = repository_ctx.path(Label("//build/kernel:build-tools/path/linux-x86/comm")),
        tmp = tmp,
        before = before,
        after = after,
    )
    args = [
        bash,
        "-e",
        "-c",
        command,
    ]
    res = repository_ctx.execute(
        args,
        timeout = 1,
        environment = env,
        working_directory = root_dir,
    )
    if res.return_code != 0:
        fail("@{name}: Fail to execute {cmd}: return_code={return_code}, stdout=\n{stdout}\nstderr=\n{stderr}".format(
            name = repository_ctx.name,
            cmd = command,
            return_code = res.return_code,
            stdout = res.stdout,
            stderr = res.stderr,
        ))
    before_content = repository_ctx.read(before)
    after_content = repository_ctx.read(after)
    new_vars = _get_new_vars(before_content, after_content, repository_ctx.name)
    dict_content = "\n".join(['{}="{}"'.format(k, v) for k, v in new_vars.items()])
    repository_ctx.file("dict.bzl", dict_content)

    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file)

    repository_ctx.file("BUILD", """
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
bzl_library(
    name = "dict",
    srcs = ["dict.bzl"],
    visibility = ["//visibility:public"],
)
""")

build_config_repo = repository_rule(
    doc = """A repository that exposes values in `build.config` files to Bazel rules.

This is similar to [`key_value_repo`](#key_value_repo), but supports a more
versatile syntax that `build.config` files uses, including `source`-ing and
multi-line variables.""",
    implementation = _impl,
    attrs = {
        "src": attr.label(
            doc = "the main entry `build.config` file to source",
            mandatory = True,
        ),
        "kernel_dir": attr.string(
            doc = "Value of `KERNEL_DIR` if the `build.config` were sourced. Default to the dirname of `src`.",
        ),
        "root_dir": attr.string(
            doc = "Value of `ROOT_DIR` if the `build.config` were sourced. It is usually `__workspace_dir__`.",
            mandatory = True,
        ),
    },
)
