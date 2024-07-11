# Copyright (C) 2024 The Android Open Source Project
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

"""A fragment config to `ddk_module_config`."""

load(
    ":common_providers.bzl",
    "DdkConfigInfo",
)

def _ddk_config_impl(ctx):
    return DdkConfigInfo(
        kconfig = depset(
            transitive = [dep[DdkConfigInfo].kconfig for dep in ctx.attr.deps] +
                         [target.files for target in ctx.attr.kconfigs],
            order = "postorder",
        ),
        defconfig = depset(
            transitive = [dep[DdkConfigInfo].defconfig for dep in ctx.attr.deps] +
                         [target.files for target in ctx.attr.defconfigs],
            order = "postorder",
        ),
    )

ddk_config = rule(
    implementation = _ddk_config_impl,
    doc = "A fragment config that configures a [`ddk_module`](#ddk_module).",
    attrs = {
        "kconfigs": attr.label_list(
            allow_files = True,
            doc = """The `Kconfig` files for this external module.

See
[`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
for its format.
""",
        ),
        "defconfigs": attr.label(
            allow_files = True,
            doc = "The `defconfig` files.",
        ),
        "deps": attr.label_list(
            providers = [DdkConfigInfo],
            doc = "Chained `ddk_config` dependency targets.",
        ),
    },
)
