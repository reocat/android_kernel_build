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
import unittest


def load_arguments():
  # Path is filled by template expansion.
  with open("{arguments_file}") as f:
    content = f.read()
  parser = argparse.ArgumentParser()
  parser.add_argument("--path")
  parser.add_argument("modules", nargs="*")
  return parser.parse_args(shlex.split(content))


arguments = load_arguments()
if arguments.path:
  os.environ["PATH"] = os.path.realpath(arguments.path)


class ScmVersionTestCase(unittest.TestCase):
  def test_contains_scmversion(self):
    """Test that all ko files has scmversion."""
    for module in arguments.modules:
      with self.subTest(module=module):
        self._assert_contains_scmversion(module)

  _scmversion_pattern = re.compile(r"scmversion=g[0-9a-f]{6,40}$")

  def _assert_contains_scmversion(self, module):
    strings = subprocess.check_output(["strings", module],
                                      text=True).strip().splitlines()
    basename = os.path.basename(module)
    self.assertTrue(any(ScmVersionTestCase._scmversion_pattern.match(s)
                        for s in strings),
                    "scmversion not found for {}".format(basename))

  _vermagic_pattern = re.compile(
    r"vermagic=[0-9]+[.][0-9]+[.][0-9]+(-[0-9]+)?-g[0-9a-f]{6,40}")

  def _assert_contains_vermagic(self, module):
    strings = subprocess.check_output(["strings", module],
                                      text=True).strip().splitlines()
    found_vermagic = [s for s in strings if s.startswith("vermagic=")]
    self.assertTrue(
        any(re.search(ScmVersionTestCase._vermagic_pattern, s) for s in
            found_vermagic),
        "no matching vermagic for {}, found {}".format(os.path.basename(module),
                                                       found_vermagic))


if __name__ == '__main__':
  unittest.main()
