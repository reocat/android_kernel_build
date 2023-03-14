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

"""Compares two ABI definitions."""

stgdiff = rule(
    implementation = _stg,
    doc = """Compares a |generated| ABI against a |reference|.""",
    attrs = {
        "reference": attr.label(
            doc = "STG baseline ABI representation.",
            allow_single_file = True,
        ),
        "generated": attr.label(
            doc = "STG produced ABI representation.",
        ),
        "reporting_formats": attr.string_list(
            doc = "Output formats.",
            default = ["plain", "flat", "small", "short", "viz"],
        ),
        "tool": attr.label(
            doc = "stgdiff binary",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
    },
)
