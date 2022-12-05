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

# Copied from the real @rules_cc//cc:defs.bzl to avoid downloading it
# from the Internet. rules_cc is needed during migration to native.X.

def cc_toolchain(**attrs):
    """Bazel cc_toolchain rule.

    https://docs.bazel.build/versions/main/be/c-cpp.html#cc_toolchain

    Args:
      **attrs: Rule attributes
    """

    # buildifier: disable=native-cc
    native.cc_toolchain(**attrs)

def cc_toolchain_suite(**attrs):
    """Bazel cc_toolchain_suite rule.

    https://docs.bazel.build/versions/main/be/c-cpp.html#cc_toolchain_suite

    Args:
      **attrs: Rule attributes
    """

    # buildifier: disable=native-cc
    native.cc_toolchain_suite(**attrs)
