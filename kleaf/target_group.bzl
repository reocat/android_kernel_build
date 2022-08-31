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

load("@bazel_skylib//lib:sets.bzl", "sets")

_TargetGroupInfo = provider(
    doc = "See [`target_group`](#target_group)",
    fields = {
        "targets_depset": "A [depset](#https://bazel.build/rules/lib/globals#depset) containing all modules in this target",
    },
)

def targets_to_depset(targets):
    """Create a [depset](#https://bazel.build/rules/lib/globals#depset) containing the given targets.

    If a target is [`target_group`](#target_group), it is expanded to contain the targets
    the [`target_group`](#target_group) refers to.
    """
    direct_deps = []
    transitive_deps = []
    for src in targets:
        if _TargetGroupInfo in src:
            transitive_deps.append(src[_TargetGroupInfo].targets_depset)
        else:
            # This is not target_group, just add it as usual
            direct_deps.append(src)
    return depset(direct_deps, transitive = transitive_deps)

def _target_group_impl(ctx):
    # See pattern in https://bazel.build/extending/rules#runfiles
    runfiles = ctx.runfiles()
    transitive_runfiles = []
    for src in ctx.attr.srcs:
        transitive_runfiles.append(src[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge_all(transitive_runfiles)

    return [
        DefaultInfo(
            files = depset(transitive = [src.files for src in ctx.attr.srcs]),
            runfiles = runfiles,
        ),
        _TargetGroupInfo(targets_depset = targets_to_depset(ctx.attr.srcs)),
    ]

target_group = rule(
    implementation = _target_group_impl,
    doc = """Create a target that expands to a list of targets.

Example usage:

```
foo(name = "foo1")
foo(name = "foo2")
bar(name = "bar", deps = [":foo1", ":foo2"])
```

With handling in the `bar`'s implementation, this can be transformed to

```
foo(name = "foo1")
foo(name = "foo2")
target_group(name = "foos", srcs = [":foo1", ":foo2"])
bar(name = "bar", deps = [":foos"])
```

To handle it properly in `bar.deps`, do the following:

1. The `bar.deps` should not expect any providers. See [attr.label_list](https://bazel.build/rules/lib/attr#label_list).
2. Expand `bar.deps` with the [`target_to_depset`](#target_to_depset) function:
   ```
   real_deps = target_to_depset(ctx.attr.deps)
   ```
   If you want to flatten the depset, use `depset.to_list()`, but note its
   [performance impact](https://bazel.build/rules/performance#avoid-depset-to-list).
""",
    attrs = {
        "srcs": attr.label_list(),
    },
)
