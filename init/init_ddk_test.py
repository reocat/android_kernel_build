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
import init_ddk

# pylint: disable=protected-access


def join(*args: Any) -> str:
    return "\n".join([*args])


_HELLO_WORLD = "Hello World!"


class KleafProjectSetterTest(parameterized.TestCase):

    @parameterized.named_parameters([
        (
            "Empty",
            "",
            join(
                init_ddk._FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                init_ddk._FILE_MARKER_END,
            ),
        ),
        (
            "BeforeNoMarkers",
            "Existing test\n",
            join(
                "Existing test",
                init_ddk._FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                init_ddk._FILE_MARKER_END,
            ),
        ),
        (
            "AfterMarkers",
            join(
                init_ddk._FILE_MARKER_BEGIN,
                init_ddk._FILE_MARKER_END,
                "Existing test after.",
            ),
            join(
                init_ddk._FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                init_ddk._FILE_MARKER_END,
                "Existing test after.",
            ),
        ),
    ])
    def test_update_file_existing(self, current_content, wanted_content):
        """Tests only text within markers are updated."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            with open(tmp_file, "w+", encoding="utf-8") as tf:
                tf.write(current_content)
            init_ddk.KleafProjectSetter._update_file(
                tmp_file, "\n" + _HELLO_WORLD
            )
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(wanted_content, got.read())

    def test_update_file_no_existing(self):
        """Tests files are created when they don't exist."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            init_ddk.KleafProjectSetter._update_file(
                tmp_file, "\n" + _HELLO_WORLD
            )
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(
                    join(
                        init_ddk._FILE_MARKER_BEGIN,
                        _HELLO_WORLD,
                        init_ddk._FILE_MARKER_END,
                    ),
                    got.read(),
                )

    def test_relevant_directories_created(self):
        """Tests corresponding directories are created if they don't exist."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_dir = pathlib.Path(temp_dir)
            ddk_workspace = temp_dir / "ddk_workspace"
            kleaf_repo = temp_dir / "kleaf_repo"
            prebuilts_dir = temp_dir / "prebuilts_dir"
            try:
                init_ddk.KleafProjectSetter(
                    argparse.Namespace(
                        build_id=None,
                        build_target=None,
                        ddk_workspace=ddk_workspace,
                        kleaf_repo=kleaf_repo,
                        local=None,
                        prebuilts_dir=prebuilts_dir,
                        url_fmt=None,
                    )
                ).run()
            except:  # pylint: disable=bare-except
                pass
            finally:
                self.assertTrue(ddk_workspace.exists())
                self.assertTrue(kleaf_repo.exists())
                self.assertTrue(prebuilts_dir.exists())

    def test_tools_bazel_symlink(self):
        """Tests a symlink to tools/bazel is correctly created."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_dir = pathlib.Path(temp_dir)
            ddk_workspace = temp_dir / "ddk_workspace"
            try:
                init_ddk.KleafProjectSetter(
                    argparse.Namespace(
                        build_id=None,
                        build_target=None,
                        ddk_workspace=ddk_workspace,
                        kleaf_repo=temp_dir / "kleaf_repo",
                        local=None,
                        prebuilts_dir=None,
                        url_fmt=None,
                    )
                ).run()
            except:  # pylint: disable=bare-except
                pass
            finally:
                tools_bazel_symlink = ddk_workspace / init_ddk._TOOLS_BAZEL
                self.assertTrue(tools_bazel_symlink.is_symlink())

    def _run_test_module_bazel_for_prebuilts(
        self,
        ddk_workspace: pathlib.Path,
        prebuilts_dir: pathlib.Path,
        expected: str,
    ):
        """Helper method for checking path in a prebuilt extension."""
        download_configs = prebuilts_dir / "download_configs.json"
        download_configs.parent.mkdir(parents=True)
        download_configs.write_text("{}")
        try:
            init_ddk.KleafProjectSetter(
                argparse.Namespace(
                    build_id=None,
                    build_target=None,
                    ddk_workspace=ddk_workspace,
                    kleaf_repo=None,
                    local=None,
                    prebuilts_dir=prebuilts_dir,
                    url_fmt=None,
                )
            ).run()
        except:  # pylint: disable=bare-except
            pass
        finally:
            module_bazel = ddk_workspace / init_ddk._MODULE_BAZEL_FILE
            self.assertTrue(module_bazel.exists())
            content = module_bazel.read_text()
            self.assertTrue(f'local_artifact_path = "{expected}",' in content)

    def test_module_bazel_for_prebuilts(self):
        """Tests prebuilts setup is correct for relative and non-relative to workspace dirs."""
        with tempfile.TemporaryDirectory() as tmp:
            ddk_workspace = pathlib.Path(tmp) / "ddk_workspace"

            # Verify the right local_artifact_path is set for prebuilts
            #  in a relative to workspace directory.
            prebuilts_dir_rel = ddk_workspace / "prebuilts_dir"
            self._run_test_module_bazel_for_prebuilts(
                ddk_workspace=ddk_workspace,
                prebuilts_dir=prebuilts_dir_rel,
                expected="prebuilts_dir",
            )

            # Verify the right local_artifact_path is set for prebuilts
            #  in a non-relative to workspace directory.
            prebuilts_dir_abs = pathlib.Path(tmp) / "prebuilts_dir"
            self._run_test_module_bazel_for_prebuilts(
                ddk_workspace=ddk_workspace,
                prebuilts_dir=prebuilts_dir_abs,
                expected=str(prebuilts_dir_abs),
            )


# This could be run as: tools/bazel test //build/kernel:init_ddk_test --test_output=all
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG, format="%(levelname)s: %(message)s"
    )
    absltest.main()
