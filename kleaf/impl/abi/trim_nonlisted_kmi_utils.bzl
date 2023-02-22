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

"""Utilities for configuring trim_nonlisted_kmi."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

FORCE_DISABLE_TRIM = "//build/kernel/kleaf/impl:force_disable_trim"
_FORCE_DISABLE_TRIM_IS_TRUE = "//build/kernel/kleaf/impl:force_disable_trim_is_true"

def _trim_nonlisted_kmi_non_config_attrs():
    """Attributes of rules that supports configuring `trim_nonlisted_kmi`."""
    return {
        "trim_nonlisted_kmi": attr.bool(),
    }

def _selected_attr(attr_val):
    return select({
        _FORCE_DISABLE_TRIM_IS_TRUE: False,
        "//conditions:default": attr_val,
    })

def _trim_nonlisted_kmi_get_value(ctx):
    """Returns the value of the real `trim_nonlisted_kmi` configuration."""
    return ctx.attr.trim_nonlisted_kmi

def _unset_trim_nonlisted_kmi_transition_impl(_settings, _attr):
    return {FORCE_DISABLE_TRIM: False}

_unset_trim_nonlisted_kmi_transition = transition(
    implementation = _unset_trim_nonlisted_kmi_transition_impl,
    inputs = [],
    outputs = [FORCE_DISABLE_TRIM],
)

trim_nonlisted_kmi_utils = struct(
    non_config_attrs = _trim_nonlisted_kmi_non_config_attrs,
    get_value = _trim_nonlisted_kmi_get_value,
    unset_transition = _unset_trim_nonlisted_kmi_transition,
    selected_attr = _selected_attr,
)
