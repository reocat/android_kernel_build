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

"""Additional `KBUILD_OPTIONS` added to a DDK module."""

SingleKbuildOptionInfo = provider(
    """An item of `KBUILD_OPTIONS`.""",
    fields = {
        "key": "variable name",
        "value": "variable value",
    },
)

KbuildOptionsInfo = provider(
    """`KBUILD_OPTIONS`.""",
    fields = {
        "kbuild_options": "A list of `SingleKbuildOptionInfo`",
    },
)

def _kbuild_options_impl(ctx):
    kbuild_options = []
    for item in ctx.attr.values:
        if "=" not in item:
            fail("{}: Value {} is not in the form KEY=value".format(ctx.label, item))
        key, value = item.split("=", 2)
        kbuild_options.append(SingleKbuildOptionInfo(key = key, value = value))

    return KbuildOptionsInfo(kbuild_options = kbuild_options)

kbuild_options = rule(
    doc = "A list of additional variables added to each Kbuild file a DDK module generates.",
    implementation = _kbuild_options_impl,
    attrs = {
        "values": attr.string_list(
            doc = """A list of `KBUILD_OPTIONS` added to a DDK module.

            Values must be in the form of `KEY=value`, e.g. `CONFIG_X=y`.
            """,
        ),
    },
)
