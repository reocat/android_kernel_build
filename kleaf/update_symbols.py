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

"""A script to update symbols in the source tree."""

import os
import shutil
import sys

runfiles_directory = os.path.dirname(__file__)
symbol_list = os.path.join(runfiles_directory, "symbol_list")
dest = os.path.join(runfiles_directory, "symlink")
try:
  symbol_list = os.path.realpath(symbol_list)
  dest = os.path.realpath(dest)
  shutil.copyfile(symbol_list, dest)
except BaseException as ex:
  sys.exit(ex)
