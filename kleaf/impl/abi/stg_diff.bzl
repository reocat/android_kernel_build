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

"""Extracts ABI information."""

stgextract = rule(
    doc = """Invokes |stg| with all the *srcs to extract the ABI information.
      If a |symbol_filter| is suplied, symbols not maching the filter are
    dropped
    
    It produces one {ctx.label}.stg file.
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
        "tool": attr.label(
            doc = "stg binary",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
    },
)
