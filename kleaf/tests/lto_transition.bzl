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

# A transition on the LTO setting. Explodes into multiple targets, each
# with a different LTO setting.
# https://bazel.build/rules/lib/transition

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")

_LTO_FLAG = "//build/kernel/kleaf:lto"

def _lto_transition_impl(settings, attr):
    return {
        value: {_LTO_FLAG: value}
        for value in LTO_VALUES
    }

lto_transition = transition(
    implementation = _lto_transition_impl,
    inputs = [],
    outputs = [_LTO_FLAG],
)
