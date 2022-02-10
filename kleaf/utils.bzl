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

def trim_nonlisted_kmi_to_string(trim_nonlisted_kmi):
    """Given a value of `trim_nonlisted_kmi`, convert it to string.

    See [`kernel_build`](#kernel_build) for a list of possible values.
    """

    # trim_nonlisted_kmi = None -> trim_nonlisted_kmi = "default_false"
    if trim_nonlisted_kmi == None:
        return "default_false"

    # trim_nonlisted_kmi = {True, False} -> trim_nonlisted_kmi = {"true", "false"}
    return str(trim_nonlisted_kmi).lower()

def should_trim(build_value, cmdline_value):
    """Decide whether trimming should be enabled.

    Args:
        build_value: value of `trim_nonlisted_kmi` in `BUILD` files
        cmdline_value: value of `--trim` in cmdline
    """

    # TRIM_NONLISTED_KMI=???; TRIM_NONLISTED_KMI=1;
    if build_value == "true":
        return True
    if build_value == "default_true":
        # TRIM_NONLISTED_KMI=${TRIM_NONLISTED_KMI:-1};
        if cmdline_value == "default":
            return True

        # TRIM_NONLISTED_KMI=1; TRIM_NONLISTED_KMI=${TRIM_NONLISTED_KMI:-1};
        if cmdline_value == "true":
            return True
    if build_value == "default_false":
        # TRIM_NONLISTED_KMI=1; TRIM_NONLISTED_KMI=${TRIM_NONLISTED_KMI:-""};
        if cmdline_value == "true":
            return True

    return False
