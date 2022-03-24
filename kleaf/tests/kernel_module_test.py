#!/usr/bin/env python3
#
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

import argparse
import os
import re
import shlex
import subprocess
import sys
import unittest


def load_arguments():
  # Path is filled by template expansion.
  with open("{arguments_file}") as f:
    content = f.read()
  parser = argparse.ArgumentParser()
  parser.add_argument("--test_tools_short_path")
  parser.add_argument("modules", nargs="*")
  return parser.parse_args(shlex.split(content))


arguments = load_arguments()
if arguments.test_tools_short_path:
  os.environ["PATH"] = os.path.realpath(arguments.test_tools_short_path)


class ScmVersionTestCase(unittest.TestCase):
  def test_contains_scmversion(self):
    """Test that all ko files has scmversion."""
    for module in arguments.modules:
      with self.subTest(module=module):
        self._assert_contains_scmversion(module)

  # TODO(b/202077908): Investigate why modinfo doesn't work for these modules
  _modinfo_exempt_list = ["spidev.ko"]
  _scmversion_pattern = r"g[0-9a-f]{6,40}"

  def _assert_contains_scmversion(self, module):
    basename = os.path.basename(module)
    try:
      scmversion = subprocess.check_output(
          ["modinfo", module, "-F", "scmversion"], text=True).strip()
    except subprocess.CalledProcessError:
      scmversion = None
    mo = re.match(ScmVersionTestCase._scmversion_pattern, scmversion)

    if basename not in ScmVersionTestCase._modinfo_exempt_list:
      self.assertTrue(mo, "no matching scmversion, found {}".format(scmversion))

  _vermagic_pattern = r"[0-9]+[.][0-9]+[.][0-9]+-android[0-9]+-[0-9]+(-[0-9]+)?-g[0-9a-f]{6,40}"

  def _assert_contains_vermagic(self, module):
    basename = os.path.basename(module)
    try:
      vermagic = subprocess.check_output(
          ["modinfo", module, "-F", "vermagic"], text=True).strip()
    except subprocess.CalledProcessError:
      vermagic = None

    mo = re.match(ScmVersionTestCase._vermagic_pattern, vermagic)

    if basename not in ScmVersionTestCase._modinfo_exempt_list:
      self.assertTrue(mo, "no matching vermagic, found {}".format(vermagic))


if __name__ == '__main__':
  unittest.main()
