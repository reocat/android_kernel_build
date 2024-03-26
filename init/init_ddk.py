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
import fnmatch
import io
import json
import logging
import os
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
_DEVICE_BAZELRC = "device.bazelrc"
_MODULE_BAZEL_FILE = "MODULE.bazel"
_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_id}/{build_target}/attempts/latest/artifacts/{filename}/url?redirect=true"
_BUILD_IDS_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/buildIds/{branch}?buildType=submitted&successful=True&maxResults=1"

_MODULE_BAZEL_CONTENT_TEMPLATE = """\
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
        self.allowed_projects: list[str] = cmd_args.allowed_projects
        self.denied_projects: list[str] = cmd_args.denied_projects
        self.headers_hack: str | None = cmd_args.headers_hack

    def _symlink_tools_bazel(self):
        # TODO: b/328770706 -- Error handling.
        # Calculate the paths.
        tools_bazel = self.ddk_workspace / _TOOLS_BAZEL
        kleaf_tools_bazel = self.kleaf_repo_dir / _TOOLS_BAZEL
        # Prepare the location and clean up if necessary
        os.makedirs(tools_bazel.parent, exist_ok=True)
        tools_bazel.unlink(missing_ok=True)

        tools_bazel.symlink_to(kleaf_tools_bazel)

    def _generate_module_bazel(self):
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        with open(module_bazel, "w", encoding="utf-8") as f:
            # TODO: b/328770706 -- Use markers to avoid overriding user overrides.
            f.write(
                _MODULE_BAZEL_CONTENT_TEMPLATE.format(
                    kleaf_repo_dir=self._try_rel_workspace(self.kleaf_repo_dir)
                )
            )
            if self.prebuilts_dir:
                f.write(
                    _MODULE_BAZEL_PREBUILTS_CONTENT_TEMPLATE.format(
                        prebuilts_dir=self._try_rel_workspace(
                            self.prebuilts_dir)
                    )
                )

    def _generate_bazelrc(self):
        bazelrc = self.ddk_workspace / _DEVICE_BAZELRC
        with open(bazelrc, "w", encoding="utf-8") as f:
            # TODO do not overwrite the file, but overwrite just a section
            f.write("common --config=internet --enable_bzlmod\n")

    def _try_rel_workspace(self, path: pathlib.Path):
        """Tries to convert |path| to be relative to ddk_workspace."""
        try:
            return path.resolve().relative_to(self.ddk_workspace)
        except ValueError:
            return path

    def _get_projects(self) -> dict[pathlib.Path, ProjectMetadata]:
        assert self.build_info, "build_info is not set!"
        project_list = self.build_info["parsed_manifest"]["projects"]
        return {project_json["path"]: project_json for project_json in project_list}

    def _project_in_group(self, project_metadata: ProjectMetadata) -> bool:
        if self.group == "default" or self.group == "all":
            return True
        return self.group in project_metadata.get("groups", [])

    def _kleaf_repo_dir_is_below_workspace(self):
        try:
            self.kleaf_repo_dir.relative_to(self.ddk_workspace)
            return True
        except ValueError:
            return False

    @staticmethod
    def _git_init(path):
        subprocess.check_call(["git", "init"], text=True, cwd=path)

    @classmethod
    def _is_git_directory(cls, path) -> bool:
        return cls._get_git_root(path) is not None

    @staticmethod
    def _get_git_root(path) -> pathlib.Path | None:
        try:
            output = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True, cwd=path
            )
            return pathlib.Path(output.strip())
        except subprocess.CalledProcessError:
            return None

    def _is_project_in_allowlist(self, project_rel_path: pathlib.Path):
        if self.allowed_projects:
            return any(fnmatch.fnmatch(str(project_rel_path), pattern) for pattern in self.allowed_projects)
        if self.denied_projects:
            return not any(fnmatch.fnmatch(str(project_rel_path), pattern) for pattern in self.denied_projects)
        return True

    def _add_submodules(self, git_root, kleaf_repo_dir, projects):
        # TODO: b/328770706: Option to use Git or repo to sync
        kleaf_repo_rel = kleaf_repo_dir.relative_to(git_root)

        if self.headers_hack:
            # The submodule might not even exist, so don't check
            subprocess.run(
                ["git", "submodule", "deinit", "-f",
                    kleaf_repo_rel / "build/kernel"],
                cwd=git_root,
            )

        # TODO: For stability, perhaps deinit before re-initializing?

        # Add submodules to Git index
        for project_metadata in projects.values():
            if not self._is_project_in_allowlist(pathlib.Path(project_metadata["path"])):
                continue
            project_path = kleaf_repo_rel / project_metadata["path"]
            subprocess.check_call(
                [
                    "git",
                    "update-index",
                    "--add",
                    "--cacheinfo",
                    "160000",
                    project_metadata["revision"],
                    project_path,
                ],
                cwd=git_root,
            )
            subprocess.check_call(
                ["git", "restore", project_path], cwd=git_root)
            subprocess.check_call(
                [
                    "git",
                    "config",
                    "-f",
                    ".gitmodules",
                    f"submodule.{project_path}.url",
                    project_metadata["remote"]["fetch"] +
                    project_metadata["name"],
                ],
                cwd=git_root,
            )
            subprocess.check_call(
                [
                    "git",
                    "config",
                    "-f",
                    ".gitmodules",
                    f"submodule.{project_path}.path",
                    project_path,
                ],
                cwd=git_root,
            )
            if project_metadata.get("cloneDepth") == "1":
                subprocess.check_call(
                    [
                        "git",
                        "config",
                        "-f",
                        ".gitmodules",
                        "--type",
                        "bool",
                        f"submodule.{project_path}.shallow",
                        "true",
                    ],
                    cwd=git_root,
                )
            # TODO also add .gitattributes

            # Checkout submodules
            # --recommend-shallow does not work. As a workaround, we manually clone with depth 1.
            args = [
                "git", "submodule", "update", "--init", "--recursive",
                "--filter=blob:none", "--jobs=8", "--recommend-shallow",
            ]
            if project_metadata.get("cloneDepth") == "1":
                args.append("--depth=1")
            args.append(project_path)
            print("+" + (" ".join([str(arg) for arg in args])))
            subprocess.check_call(args, cwd=git_root)

        # Add symlinks
        for project_metadata in projects.values():
            if not self._is_project_in_allowlist(pathlib.Path(project_metadata["path"])):
                continue
            project_abs_path = kleaf_repo_dir / project_metadata["path"]
            for link_files in project_metadata.get("linkFiles", []):
                dest = kleaf_repo_dir / link_files["dest"]
                src = project_abs_path / link_files["src"]
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.unlink(missing_ok=True)
                # Use os.path.relpath because relative_to(walk_up) is only available
                # on Python 3.12, which we don't have yet.
                dest.symlink_to(os.path.relpath(src, dest.parent))

        if self.headers_hack:
            project_metadata = projects["build/kernel"]
            if self._is_project_in_allowlist(pathlib.Path(project_metadata["path"])):
                project_abs_path = kleaf_repo_dir / project_metadata["path"]
                subprocess.check_call(
                    [
                        "git",
                        "fetch",
                        project_metadata["remote"]["fetch"] +
                        project_metadata["name"],
                        self.headers_hack,
                    ],
                    cwd=project_abs_path,
                )
                subprocess.check_call(
                    [
                        "git",
                        "reset",
                        "FETCH_HEAD",
                        "--hard",
                    ],
                    cwd=project_abs_path,
                )

    @staticmethod
    def _checkout_projects(kleaf_rep_dir, projects):
        # TODO: b/328770706: Option to use Git or repo to sync
        raise NotImplementedError

    def _set_build_info(self):
        assert self.build_id, "build_id is not set!"
        # TODO: b/328770706: This is only supported on ci.android.com
        # TODO: Relying on build_info is fragile. We should create our own mechanism.
        build_info_fp = io.BytesIO()
        self._download_artifact("BUILD_INFO", build_info_fp)
        build_info_fp.seek(0)
        self.build_info = json.load(
            io.TextIOWrapper(build_info_fp, encoding="utf-8")
        )

    def _set_build_id(self):
        # branch ~ aosp_kernel-common-android-mainline
        assert self.branch, "branch is not set!"
        build_ids_fp = io.BytesIO()
        url = _BUILD_IDS_URL_FMT.format(branch=self.branch)
        self._download(url, build_ids_fp)
        build_ids_fp.seek(0)
        build_ids_res = json.load(
            io.TextIOWrapper(build_ids_fp, encoding="utf-8"))
        # TODO: b/328770706 -- Do the appropriate handling here.
        self.build_id = build_ids_res["buildIds"][0]["buildId"]

    def _infer_download_list(self) -> list[str]:
        assert self.build_info, "build_info is not set!"
        # TODO type checking
        return self.build_info["target"]["dir_list"]

    def _download_artifact(self, remote_filename, out_f: BinaryIO, close: bool = False):
        url = self.url_fmt.format(
            build_id=self.build_id,
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        # FIXME: Move this log to the _download function.
        print(f"Scheduling download for {remote_filename}")
        self._download(url, out_f, close)

    def _download(self, url, out_f: BinaryIO, close: bool = False):
        try:
            # FIXME: For demo purposes, do not verify cert. DO NOT SUBMIT THIS!
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            with urllib.request.urlopen(url, context=ctx) as in_f:
                # print(f"Scheduling download for {remote_filename}")
                if close:
                    with out_f:
                        shutil.copyfileobj(in_f, out_f)
                else:
                    shutil.copyfileobj(in_f, out_f)
        except urllib.error.URLError:
            raise RuntimeError(f"Fail to download {url}")

    def _checkout_source_tree(self):
        assert self.build_id, "build_id is not set!"

        projects = self._get_projects()

        projects = {
            project: project_metadata
            for project, project_metadata in projects.items()
            if self._project_in_group(project_metadata)
        }

        self.kleaf_repo_dir.mkdir(parents=True, exist_ok=True)
        self.ddk_workspace.mkdir(parents=True, exist_ok=True)

        self._download_build_config_constants(projects)

        if self._kleaf_repo_dir_is_below_workspace():
            if not self._is_git_directory(self.ddk_workspace):
                self._git_init(self.ddk_workspace)
            git_root = self._get_git_root(self.ddk_workspace)
            self._add_submodules(git_root, self.kleaf_repo_dir, projects)
        else:
            self._checkout_projects(self.kleaf_repo_dir, projects)

    def _download_build_config_constants(self, projects):
        if "common" in projects:
            return

        file = "build.config.constants"
        dst = self.kleaf_repo_dir / "common" / file
        dst.unlink(missing_ok=True)
        dst.parent.mkdir(parents=True, exist_ok=True)
        with open(dst, "wb") as dst_file:
            self._download_artifact(file, dst_file)
        with open(self.kleaf_repo_dir / "common" / "BUILD.bazel", "w"):
            pass

    def _download_prebuilts(self):
        assert self.build_id, "build_id is not set!"

        if not self.prebuilts_dir:
            return

        # TODO: b/328770706: download less files
        files = self._infer_download_list()

        with concurrent.futures.ThreadPoolExecutor() as executor:
            futures = []
            for file in files:
                dst = self.prebuilts_dir / file
                dst.parent.mkdir(parents=True, exist_ok=True)
                futures.append(
                    executor.submit(self._download, file,
                                    open(dst, "wb"), close=True)
                )
            for complete_ret in concurrent.futures.as_completed(futures):
                complete_ret.result()  # Raise exception if any

    def _handle_local_kleaf(self):
        self._symlink_tools_bazel()
        self._generate_module_bazel()
        self._generate_bazelrc()

    def run(self):
        if self.branch or self.build_id:
            if not self.build_id:
                self._set_build_id()
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
    parser.add_argument(
        "--allowed_projects",
        default=[],
        action="append",
        help="Wildcard of projects to checkout only, e.g. build/kernel",
    )
    parser.add_argument(
        "--denied_projects",
        default=[],
        action="append",
        help="Wildcard of projects to not checkout, e.g. prebuilts/**",
    )
    parser.add_argument(
        "--headers_hack",
        help="Cherry-pick change to workaround ddk_headers issue",
        default=None,
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")

    try:
        KleafProjectSetter(cmd_args=args).run()
    except KleafProjectSetterError as e:
        logging.error(e, exc_info=e)
        sys.exit(1)
