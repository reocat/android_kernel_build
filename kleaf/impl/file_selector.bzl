# Copyright (C) 2023 The Android Open Source Project
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

"""Selects defconfig fragments based on flag and attribute."""

load("@bazel_skylib//lib:sets.bzl", "sets")

def _file_selector_impl(ctx):
    files_depsets = []
    for target, expected_value in ctx.attr.files.items():
        if expected_value == ctx.attr.selector:
            files_depsets.append(target.files)
    if len(files_depsets) == 0:
        fail("ERROR: {label}: selector is {selector}, but no expected value in files matches. Acceptable values: {values}".format(
            label = ctx.label,
            selector = ctx.attr.selector,
            values = sets.to_list(sets.make(ctx.attr.files.values())),
        ))
    return DefaultInfo(files = depset(transitive = files_depsets))

file_selector = rule(
    implementation = _file_selector_impl,
    doc = """Selects files based on a string during analysis phase.

This is useful when the value of the string depends on some `string_flag`,
`string_setting`, `bool_flag`, `bool_setting`, etc.

The default outputs of this target is the list of keys in `files` whose
value is equal to `selector`.

This rule is useful when you need to select files based on a flag and an
attribute simultaneously. If you only need to select files based on a flag only,
use `select()` directly. If you need to select files based on an attribute only,
do so in the rule implementation directly.

Example:

```
def myrule(
    name,
    lto = None,
):
    file_selector(
        name = name + "_lto_fragment",
        selector = select({
            "//path/to:flag_lto_is_full": "full",
            "//path/to:flag_lto_is_none": "none",
            "//conditions:default": lto or "default"
        }),
        files = {
            "//path/to:lto_full_fragment": "full",
            "//path/to:lto_none_fragment": "none",
            "//path/to:empty_filegroup": "default",
        },
    )
    _myrule(
        name = name,
        fragments = [name + "_lto_fragment"],
    )
```

In this example:

- If the `config_setting` `//path/to:flag_lto_is_full` or
  `//path/to:flag_lto_is_none` is matched
  (which usually reflects that a flag like `--lto` is set to a respective
  value), then apply the respective fragment.
- Otherwise (if the flag `--lto` is not set), check if `myrule.lto` is set.
  If so, apply the respective fragment.
- Otherwise, apply `empty_filegroup` (which usually means no fragment is
  applied).

In other words, with this setup:

- If `--lto` is set, LTO is full or none.
- Otherwise, if the target has `lto = "full"` or `lto = "none"`, LTO is that value.
- Otherwise, no fragment is provided to `_myrule`.

With this setup, `myrule.lto`
is not examined (other than a bool check) at the loading phase. `myrule.lto`
is only examined at the analysis phase.

The following setup achieves a similar effect, except that `myrule.lto`
is evaluated at the loading phase, making it less configurable.

```
def myrule(
    name,
    lto = None,
):
    if lto == None:
        default_fragment = ["//path/to:empty_filegroup"]
    elif lto == "full":
        default_fragment = ["//path/to:lto_full_fragment"]
    elif lto == "none":
        default_fragment = ["//path/to:lto_none_fragment"]
    lto_fragment = select({
        "//path/to:flag_lto_is_full": ["//path/to:lto_full_fragment"],
        "//path/to:flag_lto_is_none": ["//path/to:lto_none_fragment"],
        "//conditions:default": default_fragment,
    })
    _myrule(
        name = name,
        fragments = lto_fragment,
    )
```
""",
    attrs = {
        "selector": attr.string(
            mandatory = True,
            doc = """value in the files dictionary.

This is usually a `select()` expression. If this is a plain string, the
user should expand files or use a filegroup directly.
""",
        ),
        "files": attr.label_keyed_string_dict(
            doc = "key: label to files. value: expected selector",
            allow_files = True,
        ),
    },
)
