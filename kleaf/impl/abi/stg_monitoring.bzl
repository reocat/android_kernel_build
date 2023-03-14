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

def stg_monitoring(
        name,
        srcs = [],
        symbol_filter = None,
        reference = None,
        # TODO: Add defaults for these?
        stg_tool = None,
        stgdiff_tool = None):
    """Provide targets for abi monitoring.

    Args:
        name: Name for this suite of targets.
        srcs: Binaries with ELF information, and/or a file with ABI information in stg format.
        symbol_filter: File containing a symbol list.
        reference: Baseline ABI representation in STG format.
        stg_tool: stg binary tool.
        stgdiff_tool: stgdiff binary tool.
    """
    stgextract(
        name = name + "_extract",
        srcs = srcs,
        symbol_filter = symbol_filter,
        tool = stg_tool,
    )
    stgdiff(
        name = name + "_diff",
        generated = name + "_extract",
        reference = reference,
        tool = stgdiff_tool,
    )
