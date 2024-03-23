#!/usr/bin/env python3
#
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

"""Configures the project layout to build DDK modules."""

import argparse
import concurrent.futures
import dataclasses
import io
import json
import logging
import pathlib
import shutil
import ssl
import subprocess
import sys
import tempfile
from typing import Any, BinaryIO
import urllib.parse
import urllib.request

_TOOLS_BAZEL = "tools/bazel"
_MODULE_BAZEL_FILE = "MODULE.bazel"
_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_id}/{build_target}/attempts/latest/artifacts/{filename}/url?redirect=true"

_KLEAF_DEPENDENCY_TEMPLATE = """\
\"""Kleaf: Build Android kernels with Bazel.\"""
bazel_dep(name = "kleaf")
local_path_override(
    module_name = "kleaf",
    path = "{kleaf_repo_dir}",
)
"""

_MODULE_BAZEL_PREBUILTS_CONTENT_TEMPLATE = """\
kernel_prebuilt_ext = use_extension("@kleaf//build/kernel/kleaf:kernel_prebuilt_ext.bzl", "kernel_prebuilt_ext")
kernel_prebuilt_ext.declare_kernel_prebuilts(
    name = "gki_prebuilts",
    local_artifact_path = "{prebuilts_dir}",
    auto_download_config = True,
)
use_repo(kernel_prebuilt_ext,"gki_prebuilts")
"""


class KleafProjectSetterError(RuntimeError):
    pass


ProjectMetadata = dict[str, Any]


def _resolve(opt_path: pathlib.Path | None) -> pathlib.Path | None:
    if opt_path:
        return opt_path.resolve()
    return None


class KleafProjectSetter:
    """Initializes the layout project needed to build DDK modules."""

    def __init__(self, cmd_args: argparse.Namespace):
        self.ddk_workspace = _resolve(cmd_args.ddk_workspace)
        self.kleaf_repo_dir = _resolve(cmd_args.kleaf_repo_dir)
        self.prebuilts_dir = _resolve(cmd_args.prebuilts_dir)
        self.branch: str | None = cmd_args.branch
        self.build_id: str | None = cmd_args.build_id
        self.group: str = cmd_args.group
        self.url_fmt: str = cmd_args.url_fmt
        self.build_target: str = cmd_args.build_target

    def _symlink_tools_bazel(self):
        # TODO: b/328770706 -- Error handling.
        # Calculate the paths.
        tools_bazel = self.ddk_workspace / _TOOLS_BAZEL
        kleaf_tools_bazel = self.kleaf_repo_dir / _TOOLS_BAZEL
        # Prepare the location and clean up if necessary
        tools_bazel.parent.mkdir(parents=True, exist_ok=True)
        tools_bazel.unlink(missing_ok=True)

        tools_bazel.symlink_to(kleaf_tools_bazel)

    def _generate_module_bazel(self):
        if not self.ddk_workspace:
            return
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        with open(module_bazel, "w", encoding="utf-8") as f:
            # TODO: b/328770706 -- Use markers to avoid overriding user overrides.
            if self.kleaf_repo_dir:
                f.write(
                    _KLEAF_DEPENDENCY_TEMPLATE.format(
                        kleaf_repo_dir=self.kleaf_repo_dir
                    )
                )

    def _handle_local_kleaf(self):
        self._symlink_tools_bazel()
        self._generate_module_bazel()

    def run(self):
        if self.branch or self.build_id:
            if not self.build_id:
                pass
                # TODO: b/328770706: Infer tip of branch build id
                # self.build_id = ...
            self._set_build_info()

            if self.prebuilts_dir:
                self._download_prebuilts()

            if self.ddk_workspace and self.kleaf_repo_dir:
                self._checkout_source_tree()

        if self.ddk_workspace and self.kleaf_repo_dir:
            self._handle_local_kleaf()


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--ddk_workspace",
        help="DDK workspace root.",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--kleaf_repo_dir",
        help="Path to Kleaf's repo dir.",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--prebuilts_dir",
        help="Path to prebuilts",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--branch",
        help="Android Kernel branch from CI.",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--url_fmt",
        help="URL format endpoint for CI downloads.",
        # TODO: b/328770706 -- Set default value.
        default=_ARTIFACT_URL_FMT,
    )
    parser.add_argument(
        "--build_id",
        type=str,
        help="the build id to download the build for, e.g. 6148204",
    )
    parser.add_argument(
        "--build_target",
        type=str,
        help='the build target to download, e.g. "kernel_aarch64"',
        default="kernel_aarch64",
    )
    # TODO: make plural, just like repo init -g
    parser.add_argument(
        "--group",
        help=(
            "Group to check out. If `all`, check out all projects, including"
            " kernel sources"
        ),
        default="ddk",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")

    try:
        KleafProjectSetter(cmd_args=args).run()
    except KleafProjectSetterError as e:
        logging.error(e, exc_info=e)
        sys.exit(1)
