#!/usr/bin/env python3
#
# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A script to update a source file in the source tree."""

import os
import shutil
import sys

runfiles_directory = os.path.dirname(__file__)
src = os.path.join(runfiles_directory, "update_src")
dst = os.path.join(runfiles_directory, "update_dst")
try:
  src = os.path.realpath(src)
  dst = os.path.realpath(dst)
except BaseException as ex:
  sys.exit("ERROR: {}".format(ex))

if "-v" in sys.argv:
  print("INFO: cp {} {}".format(src, dst))

try:
  shutil.copyfile(src, dst)
except BaseException as ex:
  sys.exit("ERROR: {}".format(ex))
