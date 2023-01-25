# Copyright (C) 2023 The Android Open Source Project
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
import subprocess
import sys
import tempfile
import unittest
import gzip

from absl.testing import absltest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected_modules_list")
    parser.add_argument("--expected_modules_recovery_list")
    parser.add_argument("--expected_modules_charger_list")
    parser.add_argument("files", nargs="*", default=[])
    return parser.parse_known_args()


arguments = None


class InitramfsModulesLists(unittest.TestCase):
    def test_diff(self):
        initramfs_list = [f for f in arguments.files if os.path.basename(f) == "initramfs.img"]
        self.assertEqual(1, len(initramfs_list))
        initramfs = initramfs_list[0]
        modules_lists_map = {}

        if arguments.expected_modules_list:
            modules_lists_map["modules.load"] = arguments.expected_modules_list

        if arguments.expected_modules_recovery_list:
            modules_lists_map["modules.load.recovery"] = arguments.expected_modules_recovery_list

        if arguments.expected_modules_charger_list:
            modules_lists_map["modules.load.charger"] = arguments.expected_modules_charger_list

        with tempfile.TemporaryDirectory() as temp_dir:
            with open(initramfs) as initramfs_file:
                with subprocess.Popen(["cpio", "-i"], cwd=temp_dir,
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE) as cpio_sp:
                  with subprocess.Popen(["gzip", "-c", "-d"], stdin=initramfs_file, stdout=cpio_sp.stdin) as gzip_sp:
                    gzip_sp.communicate()
                    self.assertEqual(0, gzip_sp.returncode)

            lib_modules = os.path.join(temp_dir, "lib/modules")
            self.assertTrue(os.path.isdir(lib_modules))

            kernel_versions = os.listdir(lib_modules)
            for v in kernel_versions:
                for ml, ml_arg in modules_lists_map.items():
                    modules_load = os.path.join(lib_modules, v, ml)
                    self.assertTrue(os.path.isfile(modules_load), f"Can't find {modules_load}")

                    with open(ml_arg) as expected_modules_list_file:
                        with open(modules_load) as modules_load_file:
                            modules_load_lines = [os.path.basename(file) for file in modules_load_file.readlines()]
                            expected_modules_lines = expected_modules_list_file.readlines()
                            self.assertEqual(modules_load_lines.sort(), expected_modules_lines.sort())


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
