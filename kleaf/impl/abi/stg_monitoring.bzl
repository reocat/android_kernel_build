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

load("//build/bazel_common_rules/exec:exec.bzl", "exec")

# TODO: Use |update_source_file| from skylib once it has been moved there.
load("//build/kernel/kleaf:update_source_file.bzl", "update_source_file")
load(":abi/stg_extract.bzl", "stgextract")
load(":abi/stg_diff.bzl", "stgdiff")

# TODO Replacing these by targets when these are not pre-builts anymore.
_STG_TOOL = "//prebuilts/kernel-build-tools:linux-x86/bin/stg"
_STGDIFF_TOOL = "//prebuilts/kernel-build-tools:linux-x86/bin/stgdiff"

def stg_monitoring(
        name,
        srcs = [],
        symbol_filter = None,
        abi_reference = None):
    """Provide targets for abi monitoring.

    Args:
        name: Name for this suite of targets.
        srcs: Binaries with ELF information, and/or a file with ABI information in stg format.
        symbol_filter: File containing a symbol list.
        abi_reference: Baseline ABI representation in STG format.

    Returns:
        outputs: Artifacts from extract and diff runs.
    """

    stgextract(
        name = name + "_extract",
        srcs = srcs,
        symbol_filter = symbol_filter,
        tool = _STG_TOOL,
    )
    outputs = [name + "_extract"]

    stgdiff(
        name = name + "_diff",
        generated = name + "_extract",
        reference = abi_reference,
        tool = _STGDIFF_TOOL,
    )
    outputs.append(name + "_diff")

    # Use this filegroup to select the executable.
    native.filegroup(
        name = name + "_diff_executable",
        srcs = [name + "_diff"],
        output_group = "executable",
    )

    update_source_file(
        name = name + "_update_definition",
        src = name + "_extract",
        dst = abi_reference,
    )

    exec(
        name = name + "_update",
        data = [
            abi_reference,
            name + "_diff_executable",
            name + "_update_definition",
        ],
        script = """
            # Update abi_definition
            set -e
            $(rootpath {update_definition})
            $(rootpath {diff})
            """.format(
            diff = name + "_diff_executable",
            update_definition = name + "_update_definition",
            abi_reference = abi_reference,
        ),
    )

    return outputs
