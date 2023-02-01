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

"""Integration tests for Kleaf.

Execute at the root of the repository with:

  build/kernel/kleaf/tests/integration_test.py -- [flags to bazel]

This cannot be executed via bazel test because the script executes
bazel itself.
"""

import hashlib
import os
import shutil
import subprocess
import sys
import pathlib
import tempfile
import textwrap
import unittest

# This script is executed by integration_test.sh, not via
# bazel test, so manually modify import paths
sys.path += [
    os.getcwd(),
    f"{os.getcwd()}/external/python/absl-py"
]

from build.kernel.kleaf.analysis.inputs import analyze_inputs
from absl.testing import absltest

_BAZEL = pathlib.Path("tools/bazel")
_NOLOCAL = ["--no//build/kernel/kleaf:config_local"]
_LOCAL = ["--//build/kernel/kleaf:config_local"]
_LTO_NONE = [
    "--lto=none",
    "--nokmi_symbol_list_strict_mode",
]
# Arguments to build as fast as possible.
_FASTEST = _LOCAL + _LTO_NONE

# common package
_COMMON = "common"

bazel_args = None

class KleafIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(_BAZEL.is_file(),
                        "Bazel binary is not found -- did you execute the test under the root of "
                        "the repository?")
        self._call_bazel(["clean"])

    def _call(self, args, **kwargs) -> None:
        """Executes a shell command."""
        kwargs.setdefault("text", True)
        print(f"+ {' '.join(args)}")
        subprocess.check_call(args, **kwargs)

    def _call_bazel(self, args: list[str]) -> None:
        """Executes a bazel command."""
        self._call([str(_BAZEL)] + args + bazel_args)

    def _check_output(self, args, **kwargs) -> str:
        """Returns output of a shell command"""
        kwargs.setdefault("text", True)
        print(f"+ {' '.join(args)}")
        return subprocess.check_output(args, **kwargs)

    def _bazel(self, args: list[str]) -> str:
        """Returns output of a bazel command."""
        return self._check_output([str(_BAZEL)] + args + bazel_args)

    def _sha256(self, path: pathlib.Path | str) -> str:
        """Gets the hash for a file."""
        hash = hashlib.sha256()
        with open(path, "rb") as file:
            chunk = None
            while chunk != b'':
                chunk = file.read(4096)
                hash.update(chunk)
        return hash.hexdigest()

    def _touch(self, path: pathlib.Path | str, append_text = "\n") -> None:
        """Modifies a file so it triggers a rebuild."""
        with open(path) as file:
            old_content = file.read()

        def cleanup():
            with open(path, "w") as new_file:
                new_file.write(old_content)
        self.addCleanup(cleanup)

        with open(path, "a") as file:
            file.write(append_text)

    def _common(self) -> str:
        """Returns the common package."""
        return "common"

    def test_simple_incremental(self):
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _FASTEST)
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _FASTEST)

    def test_change_to_core_kernel_does_not_affect_modules_prepare(self):
        modules_prepare_archive = \
            f"bazel-bin/{self._common()}/kernel_aarch64_modules_prepare/modules_prepare_outdir.tar.gz"
        self._call_bazel(["build", f"//{self._common()}:kernel_aarch64_modules_prepare"] + _FASTEST)
        first_hash = self._sha256(modules_prepare_archive)

        old_modules_archive = tempfile.NamedTemporaryFile(delete=False)
        shutil.copyfile(modules_prepare_archive, old_modules_archive.name)

        self._touch(f"{self._common()}/kernel/sched/core.c")

        self._call_bazel(["build", f"//{self._common()}:kernel_aarch64_modules_prepare"] + _FASTEST)
        second_hash = self._sha256(modules_prepare_archive)

        if first_hash != second_hash:
            old_modules_archive.delete = False

        self.assertEqual(first_hash, second_hash,
                         textwrap.dedent(f"""\
                             Check their content here:
                             old: {old_modules_archive.name}
                             new: {modules_prepare_archive}"""))

    def test_module_does_not_depend_on_vmlinux(self):
        vd_modules = self._bazel([
            "query",
            'kind("^_kernel_module rule$", //common-modules/virtual-device/...)'
        ]).splitlines()
        self.assertTrue(vd_modules)

        print(f"+ build/kernel/kleaf/analysis/inputs.py 'mnemonic(\"KernelModule.*\", {vd_modules[0]})'")
        input_to_module = analyze_inputs(aquery_args = [
            f'mnemonic("KernelModule.*", {vd_modules[0]})'
        ] + _FASTEST).keys()
        self.assertFalse(
            [path for path in input_to_module if pathlib.Path(path).name == "vmlinux"],
            "An external module must not depend on vmlinux")
        self.assertFalse(
            [path for path in input_to_module if pathlib.Path(path).name == "System.map"],
            "An external module must not depend on System.map")

    def test_incremental_switch_to_local(self):
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LTO_NONE)
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LTO_NONE + _LOCAL)

    def test_incremental_switch_to_non_local(self):
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LTO_NONE + _LOCAL)
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LTO_NONE)

    def test_change_lto_to_thin_when_local(self):
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LOCAL + _LTO_NONE)
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LOCAL + [
            "--lto=thin"
        ])

    def test_change_lto_to_none_when_local(self):
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LOCAL + [
            "--lto=thin"
        ])
        self._call_bazel(["build", f"//{self._common()}:kernel_dist"] + _LOCAL + _LTO_NONE)

if __name__ == "__main__":
    bazel_args = sys.argv
    sys.argv[1:] = []
    absltest.main()