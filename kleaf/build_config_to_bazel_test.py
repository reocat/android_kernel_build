#!/usr/bin/env python3
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

import os
import sys
import tempfile
import unittest
import unittest.mock

import build_config_to_bazel

TEST_DATA = "build/kernel/kleaf/tests/build_config_to_bazel_test_data"


# This test requires buildozer installed in $HOME, which is not accessible
# via `bazel test`. Hence, execute this test with
#   build/kernel/kleaf/build_config_to_bazel_test.py
# TODO(b/241320850): Move this to bazel py_test

class BuildConfigToBazelTest(unittest.TestCase):

    def setUp(self) -> None:
        self.environ = os.environ.copy()

        self.stdout = tempfile.TemporaryFile("w+")
        self.stdout.__enter__()
        self.addCleanup(self.stdout.__exit__, None, None, None)

        self.stderr = tempfile.TemporaryFile("w+")
        self.stderr.__enter__()
        self.addCleanup(self.stderr.__exit__, None, None, None)

    def _run_test(self, name, argv=()):
        self.environ["BUILD_CONFIG"] = \
            f"{TEST_DATA}/{name}"
        argv = ["--stdout"] + list(argv)

        try:
            args = build_config_to_bazel.parse_args(argv)
            builder = build_config_to_bazel.BuildozerCommandBuilder(
                args = args,
                stdout = self.stdout,
                stderr = self.stderr,
                environ = self.environ)

            create_extra_file_obj = unittest.mock.patch.object(builder, "_create_extra_file")
            self.create_extra_file = create_extra_file_obj.__enter__()
            self.addCleanup(create_extra_file_obj.__exit__, None, None, None)

            builder.run()
        except:
            self.stderr.seek(0)
            sys.__stderr__.write(self.stderr.read())
            raise

        self.stdout.seek(0)
        self.stderr.seek(0)
        return self.stdout.read(), self.stderr.read()

    def test_simple(self):
        out, err = self._run_test("build.config.simple")
        self.assertIn('name = "simple"', out)
        self.assertIn("""srcs = glob(
        ["**"],
        exclude = [
            "**/.*",
            "**/.*/**",
            "**/BUILD.bazel",
            "**/*.bzl",
        ],
    ) + ["//common:kernel_aarch64_sources"],""", out)
        self.assertIn('build_config = "build.config.simple"', out)
        self.assertIn('name = "simple_dist"', out)

    def test_override_target_name(self):
        out, err = self._run_test("build.config.simple", ["--target=mytarget"])
        self.assertIn('name = "mytarget"', out)
        self.assertIn('name = "mytarget_dist"', out)

    def test_override_ack(self):
        out, err = self._run_test("build.config.simple", ["--ack=ack"])
        self.assertIn("//ack:kernel_aarch64", out)  # in base_kernel comments

    def test_everything(self):
        out, err = self._run_test("build.config.everything")

        # Check defined targets
        self.assertIn('"everything"', out)
        self.assertIn('"everything_dist"', out)
        self.assertIn('"everything_images"', out)
        self.assertIn('"everything_dts"', out)
        self.assertIn('"everything_modules_install"', out)

        # BUILD_CONFIG
        self.assertIn('build_config = "build.config.everything"', out)
        # BUILD_CONFIG_FRAGMENTS
        self.assertIn("build.config.fragment", out) # check comments
        self.assertIn("kernel_build_config", out) # check comments
        # FAST_BUILD
        self.assertIn("--config=fast", out) # check comments
        # LTO
        self.assertIn("--lto=thin", out) # check comments
        # FILES
        self.assertIn('"myfile/myfile1"', out)
        self.assertIn('"myfile/myfile2"', out)
        # KCONFIG_EXT_PREFIX
        self.assertIn(f'kconfig_ext = "{TEST_DATA}"', out)
        # UNSTRIPPED_MODULES
        self.assertIn("collect_unstripped_modules = True", out)
        # KMI_SYMBOL_LIST
        self.assertIn('kmi_symbol_list = "//common:android/abi_symbollist_mydevice"', out)
        # ADDITIONAL_KMI_SYMBOL_LISTS
        self.assertIn("""additional_kmi_symbol_lists = [
        "//common:android/abi_symbollist_additional1",
        "//common:android/abi_symbollist_additional2",
    ],""", out)
        # TRIM_NONLISTED_KMI
        self.assertIn("trim_nonlisted_kmi = True", out)
        # KMI_SYMBOL_LIST_STRICT_MODE
        self.assertIn("kmi_symbol_list_strict_mode = True", out)
        # KBUILD_SYMTYPES
        self.assertIn("kbuild_symtypes = True", out)
        # GENERATE_VMLINUX_BTF
        self.assertIn("generate_vmlinux_btf = True", out)

        # BUILD_BOOT_IMG
        self.assertIn("build_boot = True", out)
        # BUILD_VENDOR_BOOT_IMG
        self.assertIn("build_vendor_boot = True", out)
        # BUILD_DTBO_IMG
        self.assertIn("build_dtbo = True", out)
        # BUILD_VENDOR_KERNEL_BOOT
        self.assertIn("build_vendor_kernel_boot = True", out)
        # BUILD_INITRAMFS
        self.assertIn("build_initramfs = True", out)
        # MKBOOTIMG_PATH
        self.assertIn("mymkbootimg", out)  # check comments
        # MODULES_OPTIONS
        self.assertIn(f'modules_options = "//{TEST_DATA}:modules.options.everything"', out)
        self.create_extra_file.assert_called_with(f"{TEST_DATA}/modules.options.everything", """
option foo param=value
option bar param=value
""")

        # MODULES_BLOCKLIST
        self.assertIn('modules_blocklist = "modules_blocklist"', out)
        # MODULES_LIST
        self.assertIn('modules_list = "modules_list"', out)
        # SYSTEM_DLKM_MODULES_BLOCKLIST
        self.assertIn('system_dlkm_modules_blocklist = "system_dlkm_modules_blocklist"', out)
        # SYSTEM_DLKM_MODULES_LIST
        self.assertIn('system_dlkm_modules_list = "system_dlkm_modules_list"', out)
        # SYSTEM_DLKM_PROPS
        self.assertIn('system_dlkm_props = "system_dlkm_props"', out)
        # VENDOR_DLKM_MODULES_BLOCKLIST
        self.assertIn('vendor_dlkm_modules_blocklist = "vendor_dlkm_modules_blocklist"', out)
        # VENDOR_DLKM_MODULES_LIST
        self.assertIn('vendor_dlkm_modules_list = "vendor_dlkm_modules_list"', out)
        # VENDOR_DLKM_PROPS
        self.assertIn('vendor_dlkm_props = "vendor_dlkm_props"', out)

        # GKI_BUILD_CONFIG
        self.assertIn('base_kernel = "//common:kernel_aarch64"', out)
        # GKI_PREBUILTS_DIR
        self.assertIn("prebuilts/gki", out)  # check comments

        # DTS_EXT_DIR
        self.assertIn(f'dtstree = "//{TEST_DATA}:everything_dts"', out)

        # BUILD_GKI_CERTIFICATION_TOOLS
        self.assertIn(f'"//build/kernel:gki_certification_tools"', out)

        # TODO(b/241320850): Support these variables in build_config_to_bazel
        self.assertIn("EXT_MODULES", out)
        self.assertIn("ABI_DEFINITION", out)
        self.assertIn("KMI_ENFORCED", out)


if __name__ == '__main__':
    unittest.main(verbosity=2)
