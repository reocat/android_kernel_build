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

load("//build/kernel/kleaf:workspace.bzl", "define_kleaf_workspace")

# The following 2 repositories contain prebuilts that are necessary to the Java Rules.
# They are vendored locally to avoid the need for CI bots to download them.
local_repository(
    name = "remote_java_tools",
    path = "prebuilts/bazel/common/remote_java_tools",
)

local_repository(
    name = "remote_java_tools_linux",
    path = "prebuilts/bazel/linux-x86_64/remote_java_tools_linux",
)

# TODO(b/200202912): Re-route this when rules_python is pulled into AOSP.
local_repository(
    name = "rules_python",
    path = "build/bazel_common_rules/rules/python/stubs",
)

define_kleaf_workspace()

# The vendored rules_java repository.
local_repository(
    name = "rules_java",
    path = "external/bazelbuild-rules_java",
)

# Optional epilog for analysis testing.
load("//build/kernel/kleaf:workspace_epilog.bzl", "define_kleaf_workspace_epilog")

define_kleaf_workspace_epilog()
