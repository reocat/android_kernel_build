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

"""Utilities for forcefully adding vmlinux to kernel_build."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

_FORCE_ADD_VMLINUX_SETTING = "//build/kernel/kleaf/impl:force_add_vmlinux"

def _force_add_vmlinux_config_settings_raw():
    """Attributes of rules that supports adding vmlinux via outgoing-edge transitions."""
    return {
        "_force_add_vmlinux": _FORCE_ADD_VMLINUX_SETTING,
    }

def _force_add_vmlinux_get_value(ctx):
    """Returns the value of the `force_add_vmlinux` configuration."""
    return ctx.attr._force_add_vmlinux[BuildSettingInfo].value

force_add_vmlinux_utils = struct(
    config_settings_raw = _force_add_vmlinux_config_settings_raw,
    get_value = _force_add_vmlinux_get_value,
)
