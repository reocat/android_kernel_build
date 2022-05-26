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

KernelUnstrippedModulesInfo = provider(
    doc = "A provider that provides unstripped modules",
    fields = {
        "base_kernel": "the `base_kernel` target, if exists",
        "directory": """A [`File`](https://bazel.build/rules/lib/File) that
points to a directory containing unstripped modules.

For [`kernel_build()`](#kernel_build), this is a directory containing unstripped in-tree modules.
- This is `None` if and only if `collect_unstripped_modules = False`
- Never `None` if and only if `collect_unstripped_modules = True`
- An empty directory if and only if `collect_unstripped_modules = True` and `module_outs` is empty

For an external [`kernel_module()`](#kernel_module), this is a directory containing unstripped external modules.
- This is `None` if and only if the `kernel_build` argument has `collect_unstripped_modules = False`
- Never `None` if and only if the `kernel_build` argument has `collect_unstripped_modules = True`
""",
    },
)
