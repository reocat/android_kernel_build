# Copyright (C) 2024 The Android Open Source Project
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

"""Tests for init_ddk.py"""

import argparse
import logging
import pathlib
import tempfile
from typing import Any

from absl.testing import absltest
from absl.testing import parameterized
from init_ddk import (
    KleafProjectSetter,
    _FILE_MARKER_BEGIN,
    _FILE_MARKER_END,
    _TOOLS_BAZEL,
)

# pylint: disable=protected-access


def join(*args: Any) -> str:
    return "\n".join([*args])


_HELLO_WORLD = "Hello World!"


class KleafProjectSetterTest(parameterized.TestCase):

    @parameterized.named_parameters([
        ("Empty", "", join(_FILE_MARKER_BEGIN, _HELLO_WORLD, _FILE_MARKER_END)),
        (
            "BeforeNoMarkers",
            "Existing test\n",
            join(
                "Existing test",
                _FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                _FILE_MARKER_END,
            ),
        ),
        (
            "AfterMarkers",
            join(_FILE_MARKER_BEGIN, _FILE_MARKER_END, "Existing test after."),
            join(
                _FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                _FILE_MARKER_END,
                "Existing test after.",
            ),
        ),
    ])
    def test_update_file_existing(self, current_content, wanted_content):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            with open(tmp_file, "w+", encoding="utf-8") as tf:
                tf.write(current_content)
            KleafProjectSetter._update_file(tmp_file, "\n" + _HELLO_WORLD)
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(wanted_content, got.read())

    def test_update_file_no_existing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            KleafProjectSetter._update_file(tmp_file, "\n" + _HELLO_WORLD)
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(
                    join(_FILE_MARKER_BEGIN, _HELLO_WORLD, _FILE_MARKER_END),
                    got.read(),
                )

    def test_create_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            ddk_workspace = pathlib.Path(tmp) / "ddk_workspace"
            kleaf_repo = pathlib.Path(tmp) / "kleaf_repo"
            prebuilts_dir = pathlib.Path(tmp) / "prebuilts_dir"
            obj = KleafProjectSetter(
                argparse.Namespace(
                    build_id=None,
                    build_target=None,
                    ddk_workspace=ddk_workspace,
                    kleaf_repo=kleaf_repo,
                    local=None,
                    prebuilts_dir=prebuilts_dir,
                    url_fmt=None,
                )
            )
            try:
                obj.run()
            except Exception as e:  # pylint: disable=broad-exception-caught
                logging.warning(e)
            finally:
                self.assertTrue(ddk_workspace.exists())
                self.assertTrue(kleaf_repo.exists())
                self.assertTrue(prebuilts_dir.exists())

    def test_tools_bazel_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            ddk_workspace = pathlib.Path(tmp) / "ddk_workspace"
            tools_bazel_symlink = ddk_workspace / _TOOLS_BAZEL
            obj = KleafProjectSetter(
                argparse.Namespace(
                    build_id=None,
                    build_target=None,
                    ddk_workspace=ddk_workspace,
                    kleaf_repo=pathlib.Path(tmp) / "kleaf_repo",
                    local=None,
                    prebuilts_dir=None,
                    url_fmt=None,
                )
            )
            try:
                obj.run()
            except Exception as e:  # pylint: disable=broad-exception-caught
                logging.warning(e)
            finally:
                self.assertTrue(tools_bazel_symlink.is_symlink())


# This could be run as: tools/bazel test //build/kernel:init_ddk_test --test_output=all
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG, format="%(levelname)s: %(message)s"
    )
    absltest.main()
