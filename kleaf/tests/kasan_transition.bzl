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

# A transition on the kasan setting. Explodes into multiple targets, each
# with a different kasan setting.
# https://bazel.build/rules/lib/transition

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

_KASAN_FLAG = "//build/kernel/kleaf:kasan"

def _kasan_transition_impl(settings, attr):
    return {
        "kasan": {_KASAN_FLAG: True},
        "nokasan": {_KASAN_FLAG: False},
    }

kasan_transition = transition(
    implementation = _kasan_transition_impl,
    inputs = [],
    outputs = [_KASAN_FLAG],
)
