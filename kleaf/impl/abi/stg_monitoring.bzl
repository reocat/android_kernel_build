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

"""Rules for ABI monitoring around STG tools."""

load(":abi/stg_extract.bzl", "stgextract")
load(":abi/stg_diff.bzl", "stgdiff")

# NOTE: When used outside Kleaf these constants should be updated accordingly.
_STG_TOOL = "//prebuilts/kernel-build-tools:linux-x86/bin/stg"
_STGDIFF_TOOL = "//prebuilts/kernel-build-tools:linux-x86/bin/stgdiff"

# TODO(Remove after placing them inside the rule implementation).
stgextract(name = "no-extract", tool = _STG_TOOL)
stgdiff(name = "no-diff", tool = _STGDIFF_TOOL)

stg_monitoring = rule(
    doc = """TODO: Add docs
    """,
    attrs = {
        "srcs": atr.label_ist(
            doc = """Binaries with ELF information.
            And/or files with ABI information in stg format.""",
            allow_files = True,
        ),
        "symbol_filter": attr.label(
            doc = "File containing a symbol list.",
        ),
        "reference": attr.label(
            doc = "STG baseline ABI representation.",
            allow_single_file = True,
        ),
    },
)
