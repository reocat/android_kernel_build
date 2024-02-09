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

"""Declares location of build.config.constants for kleaf_docs
"""

load("//build/kernel/kleaf/bzlmod:make_kernel_toolchain_ext.bzl", "make_kernel_toolchain_ext")

visibility("public")

kernel_toolchain_ext = make_kernel_toolchain_ext(
    toolchain_constants = "//build/kernel/kleaf/bzlmod:docs_build.config.constants",
)
