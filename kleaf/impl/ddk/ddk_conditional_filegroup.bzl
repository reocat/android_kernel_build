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

"""Sources conditional to a [`ddk_module`](#ddk_module)."""

DDK_CONDITIONAL_TRUE = "__kleaf_ddk_conditional_srcs_true_value"

DdkConditionalFilegroupInfo = provider(
    "Provides attributes for [`ddk_conditional_filegroup`](#ddk_conditional_filegroup)",
    fields = {
        "config": "ddk_conditional_filegroup.config",
        "value": """ddk_conditional_filegroup.value

This may be a special value `True` when it is set to `True` in `ddk_module`.
        """,
    },
)

def _ddk_conditional_filegroup_impl(ctx):
    value = ctx.attr.value
    if value == DDK_CONDITIONAL_TRUE:
        value = True

    return [
        DefaultInfo(files = depset(transitive = [target.files for target in ctx.attr.srcs])),
        DdkConditionalFilegroupInfo(
            config = ctx.attr.config,
            value = value,
        ),
    ]

_ddk_conditional_filegroup = rule(
    implementation = _ddk_conditional_filegroup_impl,
    doc = """A target that declares sources conditionally included based on configs.

Example:

```
ddk_conditional_filegroup(
    name = "srcs_when_foo_is_set",
    config = "CONFIG_FOO",
    value = "y",
    srcs = ["foo_is_set.c"]
)

ddk_module(
    name = "mymodule",
    srcs = [
        ":srcs_when_foo_is_set",
    ],
    ...
)
```

In the above example, `foo_is_set.c` is only included in `mymodule.ko`
if `CONFIG_FOO=y`:

```
ifeq ($(CONFIG_FOO),y)
obj-y += foo_is_set.c
endif
```

A special value `DDK_CONDITIONAL_TRUE` means `y` or `m`. Example:

```
ddk_conditional_filegroup(
    name = "srcs_when_foo_is_set",
    config = "CONFIG_FOO",
    value = DDK_CONDITIONAL_TRUE,
    srcs = ["foo_is_set.c"]
)

ddk_module(
    name = "mymodule",
    srcs = [
        ":srcs_when_foo_is_set",
    ],
    ...
)
```

This generates:

```
obj-$(CONFIG_FOO) += foo_is_set.c
```

Note that during the analysis phase, `foo_is_set.c` is always an input
to `mymodule`, so any change to `foo_is_set.c` will trigger a rebuild
on `mymodule` regardless of the value of `CONFIG_FOO`. The conditional
is only examined in Kbuild.
    """,
    attrs = {
        "config": attr.string(
            mandatory = True,
            doc = "Name of the config with the `CONFIG_` prefix.",
        ),
        "value": attr.string(
            mandatory = True,
            doc = """Expected value of the config.

If and only if the config matches this value, `srcs` are included.

This should be set to `DDK_CONDITIONAL_TRUE` when `True` is in
`ddk_modules.conditional_srcs`.
""",
        ),
        "srcs": attr.label_list(
            allow_files = [".c", ".h", ".s", ".rs"],
            doc = "See [`ddk_module.srcs`](#ddk_module-srcs).",
        ),
    },
)

def ddk_conditional_filegroup(
    name,
    config,
    value,
    srcs = None,
    **kwargs
):
    """Wrapper macro of _ddk_conditional_filegroup.

    Args:
        name: name of target
        config: Name of the config with the `CONFIG_` prefix.
        value: Expected value of the config.

          This value may be:

          - `True`: maps to `obj-$(CONFIG_FOO) += xxx`
          - `False`: maps to empty string, see below
          - a string: maps to `ifeq ($(CONFIG_FOO),the_expected_value)`

        srcs: See [`ddk_module.srcs`](#ddk_module-srcs).
        **kwargs: kwargs
    """
    if value == True:
        value = DDK_CONDITIONAL_TRUE
    elif value == False:
        value = ""

    _ddk_conditional_filegroup(
        name = name,
        config = config,
        value = value,
        srcs = srcs,
        **kwargs
    )
