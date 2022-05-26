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

# Providers that are only provided by `kernel_build` and `kernel_filegroup`.

KernelBuildInfo = provider(
    doc = """Generic information provided by a `kernel_build`.""",
    fields = {
        "out_dir_kernel_headers_tar": "Archive containing headers in `OUT_DIR`",
        "outs": "A list of File object corresponding to the `outs` attribute (excluding `module_outs`, `implicit_outs` and `internal_outs`)",
        "base_kernel_files": "[Default outputs](https://docs.bazel.build/versions/main/skylark/rules.html#default-outputs) of the rule specified by `base_kernel`",
        "interceptor_output": "`interceptor` log. See [`interceptor`](https://android.googlesource.com/kernel/tools/interceptor/) project.",
    },
)

KernelBuildExtModuleInfo = provider(
    doc = "A provider that specifies the expectations of a `_kernel_module` (an external module) or a `kernel_modules_install` from its `kernel_build` attribute.",
    fields = {
        "modules_staging_archive": "Archive containing staging kernel modules. " +
                                   "Does not contain the lib/modules/* suffix.",
        "module_srcs": "sources for this kernel_build for building external modules",
        "modules_prepare_setup": "A command that is equivalent to running `make modules_prepare`. Requires env setup.",
        "modules_prepare_deps": "A list of deps to run `modules_prepare_cmd`.",
        "collect_unstripped_modules": "Whether an external [`kernel_module`](#kernel_module) building against this [`kernel_build`](#kernel_build) should provide unstripped ones for debugging.",
    },
)

KernelBuildUapiInfo = provider(
    doc = "A provider that specifies the expecation of a `merged_uapi_headers` rule from its `kernel_build` attribute.",
    fields = {
        "base_kernel": "the `base_kernel` target, if exists",
        "kernel_uapi_headers": "the `*_kernel_uapi_headers` target",
    },
)

KernelBuildAbiInfo = provider(
    doc = "A provider that specifies the expectations of a [`kernel_abi`](#kernel_abi) on a `kernel_build`.",
    fields = {
        "trim_nonlisted_kmi": "Value of `trim_nonlisted_kmi` in [`kernel_build()`](#kernel_build).",
        "combined_abi_symbollist": "The **combined** `abi_symbollist` file from the `_kmi_symbol_list` rule, consist of the source `kmi_symbol_list` and `additional_kmi_symbol_lists`.",
        "module_outs_file": "A file containing `[kernel_build.module_outs]`(#kernel_build-module_outs).",
    },
)

KernelBuildInTreeModulesInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](#kernel_build) on its
[`base_kernel`](#kernel_build-base_kernel) or [`base_kernel_for_module_outs`](#kernel_build-base_kernel_for_module_outs).""",
    fields = {
        "module_outs_file": "A file containing `[kernel_build.module_outs]`(#kernel_build-module_outs).",
    },
)
