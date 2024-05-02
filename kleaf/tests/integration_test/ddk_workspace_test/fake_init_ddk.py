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

# TODO: This functionality should be moved into init_ddk.py

"""Script that fakes the behavior of init_ddk.py for testing."""

import argparse
import pathlib
import textwrap


class FakeInitDdk:
    """Additional fix-ups after init_ddk.py for integration tests."""

    def __init__(self, kleaf_repo_rel: pathlib.Path,
                 ddk_workspace: pathlib.Path):
        """Initializes the object.

        Args:
            kleaf_repo_rel: path to @kleaf. Its value will be used as-is.
            ddk_workspace: path to DDK workspace. Its value will be used as-is.
        """
        self.kleaf_repo_rel = kleaf_repo_rel
        self.ddk_workspace = ddk_workspace

    def _generate_device_bazelrc(self):
        path = self.ddk_workspace / "device.bazelrc"
        with open(path, "r+", encoding="utf-8") as out_file:
            lines = [line for line in out_file
                     if "--config=internet" not in line]
            out_file.seek(0)
            out_file.write("".join(lines))
            out_file.truncate()

    def _generate_module_bazel(self):
        path = self.ddk_workspace / "MODULE.bazel"
        with open(path, "a", encoding="utf-8") as out_file:
            print(textwrap.dedent("""\
                bazel_dep(name = "bazel_skylib")
            """), file=out_file)

            # Copy local_path_override() from @kleaf because we do not
            # have Internet on CI.
            kleaf_repo = self.ddk_workspace / self.kleaf_repo_rel
            kleaf_module_bazel_path = kleaf_repo / "MODULE.bazel"
            with open(kleaf_module_bazel_path, encoding="utf-8") as src:
                self._copy_local_path_override(src, out_file)

    def _copy_local_path_override(self, src, dst):
        """Naive algoritm to parse src and copy local_path_override() to dst"""
        section = []
        module_name_attr_prefix = 'module_name = "'
        path_attr_prefix = 'path = "'

        # Skip rules_rust because it is a dev_dependency.
        # Modify path so it is relative to the current DDK workspace.
        for line in src:
            if line.startswith("local_path_override("):
                section.append(line)
                continue
            if section:
                if line.lstrip().startswith(module_name_attr_prefix):
                    if '"rules_rust"' in line:
                        section = []
                        continue
                elif line.lstrip().startswith(path_attr_prefix):
                    line = line.strip()
                    line = line.removeprefix(
                        path_attr_prefix).removesuffix('",')
                    line = f'    path = "{self.kleaf_repo_rel / line}",\n'
                section.append(line)

                if line.strip() == ")":
                    print("".join(section), file=dst)
                    section.clear()

    def _generate_workspace_bzlmod(self):
        """Generates an empty WORKSPACE.bzlmod to workaround rules_cc error."""
        path = self.ddk_workspace / "WORKSPACE.bzlmod"
        with open(path, "w", encoding="utf-8") as _:
            pass

    def run(self):
        self._generate_device_bazelrc()
        self._generate_module_bazel()
        self._generate_workspace_bzlmod()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kleaf_repo_rel",
                        type=pathlib.Path,
                        help="If relative, it is against ddk_workspace",
                        )
    parser.add_argument("--ddk_workspace",
                        type=pathlib.Path,
                        help="If relative, it is against cwd",)
    args = parser.parse_args()
    FakeInitDdk(**vars(args)).run()
