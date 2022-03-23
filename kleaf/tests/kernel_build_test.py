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
import os.path
import re
import shlex
import subprocess

import unittest
import argparse


def load_arguments():
    # Path is filled by template expansion.
    with open("{arguments_file}") as f:
        content = f.read()
    parser = argparse.ArgumentParser()
    parser.add_argument("--test_tools_short_path")
    parser.add_argument("artifacts", nargs="*")
    return parser.parse_args(shlex.split(content))


arguments = load_arguments()
if arguments.test_tools_short_path:
    os.environ["PATH"] = os.path.realpath(arguments.test_tools_short_path)


class ScmVersionTestCase(unittest.TestCase):
    # Version.PatchLevel.SubLevel-AndroidRelease-KmiGeneration[-Tag]-Sha1
    # e.g. 5.4.42-android12-0-00544-ged21d463f856
    # e.g. 5.4.42-mainline-00544-ged21d463f856
    _scmversion_pattern = re.compile(
        r"Linux version [0-9]+[.][0-9]+[.][0-9]+(-android[0-9]+-[0-9]+|-mainline)(-[0-9]+)?-g[0-9a-f]{12,40}")

    def test_vmlinux_contains_scmversion(self):
        """Test that vmlinux (if exists) has scmversion."""
        for artifact in arguments.artifacts:
            if os.path.basename(artifact) != "vmlinux":
                continue
            strings = subprocess.check_output(["strings", artifact],
                                              text=True).strip().splitlines()
            matches = any(ScmVersionTestCase._scmversion_pattern.search(s)
                          for s in strings)
            msg = "scmversion not found for vmlinux, found {}".format(
                [s for s in strings if "Linux version" in s]
            )
            self.assertTrue(matches, msg)

if __name__ == '__main__':
    unittest.main()
