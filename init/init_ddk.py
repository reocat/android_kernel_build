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
import json
import logging
from os import set_blocking
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
from typing import TextIO
import urllib.parse
import xml.dom.minidom
import xml.parsers.expat

_TOOLS_BAZEL = "tools/bazel"
_DEVICE_BAZELRC = "device.bazelrc"
_FILE_MARKER_BEGIN = "### GENERATED SECTION - DO NOT MODIFY - BEGIN ###\n"
_FILE_MARKER_END = "### GENERATED SECTION - DO NOT MODIFY - END ###\n"
_MODULE_BAZEL_FILE = "MODULE.bazel"
_KLEAF_MANIFEST = "kleaf.xml"

_KLEAF_DEPENDENCY_TEMPLATE = """\
\"""Kleaf: Build Android kernels with Bazel.\"""
bazel_dep(name = "kleaf")
local_path_override(
    module_name = "kleaf",
    path = "{kleaf_repo_relative}",
)
"""

_LOCAL_PREBUILTS_CONTENT_TEMPLATE = """\
kernel_prebuilt_ext = use_extension(
    "@kleaf//build/kernel/kleaf:kernel_prebuilt_ext.bzl",
    "kernel_prebuilt_ext",
)
kernel_prebuilt_ext.declare_kernel_prebuilts(
    name = "gki_prebuilts",
    local_artifact_path = "{prebuilts_dir_relative}",
)
use_repo(kernel_prebuilt_ext, "gki_prebuilts")
"""


class KleafProjectSetterError(RuntimeError):
    pass


@dataclasses.dataclass(kw_only=True)
class KleafProjectSetter:
    """Configures the project layout to build DDK modules."""

    build_id: str | None
    build_target: str | None
    ddk_workspace: pathlib.Path | None
    local: bool
    kleaf_repo: pathlib.Path | None
    prebuilts_dir: pathlib.Path | None
    url_fmt: str | None
    superproject_tool: str
    dryrun_checkout: bool

    def _symlink_tools_bazel(self):
        """Creates the symlink tools/bazel."""
        if not self.ddk_workspace or not self.kleaf_repo:
            return
        # Calculate the paths.
        tools_bazel = self.ddk_workspace / _TOOLS_BAZEL
        kleaf_tools_bazel = self.kleaf_repo / _TOOLS_BAZEL
        # Prepare the location and clean up if necessary.
        tools_bazel.parent.mkdir(parents=True, exist_ok=True)
        tools_bazel.unlink(missing_ok=True)
        tools_bazel.symlink_to(kleaf_tools_bazel)

    @staticmethod
    def _update_file(path: pathlib.Path, update: str):
        """Updates the content of a section between markers in a file."""
        add_content: bool = False
        skip_line: bool = False
        update_written: bool = False
        if path.exists():
            open_mode = "r"
            logging.info("Updating file %s.", path)
        else:
            open_mode = "a+"
            logging.info("Creating file %s.", path)
        with (
            open(path, open_mode, encoding="utf-8") as input_file,
            tempfile.NamedTemporaryFile(mode="w", delete=False) as output_file,
        ):
            for line in input_file:
                if add_content:
                    output_file.write(_FILE_MARKER_BEGIN)
                    output_file.write(update + "\n")
                    update_written = True
                    add_content = False
                if _FILE_MARKER_END in line:
                    skip_line = False
                if _FILE_MARKER_BEGIN in line:
                    skip_line = True
                    add_content = True
                if not skip_line:
                    output_file.write(line)
            if not update_written:
                output_file.write(_FILE_MARKER_BEGIN)
                output_file.write(update + "\n")
                output_file.write(_FILE_MARKER_END)
        shutil.move(output_file.name, path)

    def _try_rel_workspace(self, path: pathlib.Path):
        """Tries to convert |path| to be relative to ddk_workspace."""
        if not self.ddk_workspace:
            raise KleafProjectSetterError(
                "ERROR: _try_rel_workspace called without --ddk_workspace set!"
            )
        try:
            return path.relative_to(self.ddk_workspace)
        except ValueError:
            logging.warning(
                "Path %s is not relative to DDK workspace %s, using absolute"
                " path.",
                path,
                self.ddk_workspace,
            )
            return path

    def _get_local_path_overrides(self):
        """Naive algorithm to extract local_path_override()'s from local @kleaf."""
        path_attr_prefix = 'path = "'
        section = []
        overrides = []
        module_bazel = self.kleaf_repo / _MODULE_BAZEL_FILE
        # Modify path so it is relative to the current DDK workspace.
        kleaf_repo = self._try_rel_workspace(self.kleaf_repo)
        with open(module_bazel, "r", encoding="utf-8") as src:
            for line in src:
                if line.startswith("local_path_override("):
                    section.append(line)
                    continue
                if not section:
                    continue
                elif line.lstrip().startswith(path_attr_prefix):
                    line = line.strip().removeprefix(path_attr_prefix)
                    line = line.removesuffix('",')
                    line = f'    path = "{kleaf_repo / line}",\n'
                section.append(line)
                if line.strip() == ")":
                    overrides.append("".join(section))
                    section.clear()
        return "".join(overrides)

    def _generate_module_bazel(self):
        """Configures the dependencies for the DDK workspace."""
        if not self.ddk_workspace:
            return
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        module_bazel_content = ""
        if self.kleaf_repo:
            module_bazel_content += _KLEAF_DEPENDENCY_TEMPLATE.format(
                kleaf_repo_relative=self._try_rel_workspace(self.kleaf_repo),
            )
            module_bazel_content += self._get_local_path_overrides()

            # https://github.com/bazelbuild/bazel/issues/22579
            # @@rules_cc is implicitly added in a fallback
            # WORKSPACE file if the file doesn't exist.
            # Work around the issue by adding an empty file.
            if (not (self.ddk_workspace / "WORKSPACE").is_file() and
                not (self.ddk_workspace / "WORKSPACE.bazel").is_file() and
                not (self.ddk_workspace / "WORKSPACE.bzlmod").is_file()):
                (self.ddk_workspace / "WORKSPACE.bzlmod").touch()

        if self.prebuilts_dir:
            module_bazel_content += "\n"
            module_bazel_content += _LOCAL_PREBUILTS_CONTENT_TEMPLATE.format(
                # The prebuilts directory must be relative to the DDK workspace.
                prebuilts_dir_relative=self._try_rel_workspace(
                    self.prebuilts_dir
                ),
            )
        if not module_bazel_content:
            logging.info("Nothing to update in %s", module_bazel)
        self._update_file(module_bazel, module_bazel_content)

    def _generate_bazelrc(self):
        """Creates a Bazel configuration file with the minimum setup required."""
        if not self.ddk_workspace or not self.kleaf_repo:
            return
        bazelrc = self.ddk_workspace / _DEVICE_BAZELRC

        kleaf_repo = self._try_rel_workspace(self.kleaf_repo)
        if not kleaf_repo.is_absolute():
            kleaf_repo = pathlib.Path("%workspace%") / kleaf_repo

        bazelrc_content = []
        bazelrc_content.append((
            "common"
            f" --registry=file://{kleaf_repo}/external/bazelbuild-bazel-central-registry"
        ))
        # Explicitly disable internet usage.
        bazelrc_content.append("common --config=no_internet")

        self._update_file(
            bazelrc,
            "\n".join(bazelrc_content),
        )

    def _get_url(self, remote_filename: str) -> str | None:
        """Returns a valid url when it can be formed with target and id."""
        if not self.url_fmt:
            raise KleafProjectSetterError(
                "ERROR: _get_url called without url_fmt set!"
            )
        url = self.url_fmt.format(
            build_id=self.build_id,
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        url_with_fake_id = self.url_fmt.format(
            build_id="__FAKE_BUILD_NUMBER_PLACEHOLDER__",
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        if not self.build_id and url != url_with_fake_id:
            return None
        return url

    def _can_download_artifacts(self):
        """Validates that download are possible within the current context."""
        if not self.url_fmt:
            return False
        # Check if build_id is missing and url_fmt has an anchor depending on it.
        if self._get_url("") is None:
            return False
        return True

    def _download(
        self,
        remote_filename: str,
        out_file_name: pathlib.Path,
        mandatory: bool = True,
    ) -> None:
        """Given the url_fmt, build_id and build_target downloads a remote file.

        Args:
            remote_filename: File name for the file, it can contain anchors for,
              build_id, target and filename.
            out_file_name: Destination place for the download.
            mandatory: When set to true, the download fails when the file could
              not be downloaded.
        """
        url = self._get_url(remote_filename)
        if not url:
            raise KleafProjectSetterError(
                f"ERROR: Unable to download {remote_filename}: can't infer URL"
            )
        # Workaround: Rely on host keychain to download files.
        # This is needed otheriwese downloads fail when running this script
        #   using the hermetic Python toolchain.
        subprocess.run(
            [
                "python3",
                pathlib.Path(__file__).parent / "init_download.py",
                url,
                out_file_name,
            ],
            stderr=subprocess.STDOUT if mandatory else subprocess.DEVNULL,
            check=mandatory,
        )

    def _download_meta_files(self):
        if self.prebuilts_dir:
            self._download_meta_files_to(self.prebuilts_dir)
        else:
            with tempfile.TemporaryDirectory() as meta_files_dir:
                self._download_meta_files_to(pathlib.Path(meta_files_dir))

    def _download_meta_files_to(self, meta_files_dir: pathlib.Path):
        meta_files_dir.mkdir(parents=True, exist_ok=True)
        self._download_list = self._infer_download_list(meta_files_dir)
        self._repo_manifest_of_build = self._download_repo_manifest_of_build(
            meta_files_dir)

    def _infer_download_list(self, meta_files_dir: pathlib.Path) \
        -> dict[str, dict]:
        """Infers the list of files to be downloaded using download_configs.json."""
        download_configs = meta_files_dir / "download_configs.json"
        if self._can_download_artifacts():
            with open(download_configs, "w+", encoding="utf-8") as f:
                self._download("download_configs.json", pathlib.Path(f.name))
                return json.load(f)
        with open(download_configs, "r") as f:
            return json.load(f)

    def _download_repo_manifest_of_build(self, meta_files_dir: pathlib.Path) \
        -> str:
        local_filename = "manifest.xml"
        config = self._download_list[local_filename]
        remote_filename = config["remote_filename_fmt"].format(
            build_number = self.build_id,
        )
        dst = meta_files_dir / local_filename
        dst.parent.mkdir(parents=True, exist_ok=True)
        self._download(remote_filename, dst, config["mandatory"])
        with open(dst) as f:
            return f.read()

    def _download_prebuilts(self) -> None:
        """Downloads prebuilts from a given build_id when provided."""
        if not self.prebuilts_dir:
            raise KleafProjectSetterError(
                "ERROR: _download_prebuilts called without --prebuilts_dir!"
            )
        logging.info("Downloading prebuilts into %s", self.prebuilts_dir)
        with concurrent.futures.ThreadPoolExecutor() as executor:
            futures = []
            for local_filename, config in self._download_list.items():
                remote_filename = config["remote_filename_fmt"].format(
                    build_number = self.build_id,
                )
                dst = self.prebuilts_dir / local_filename
                dst.parent.mkdir(parents=True, exist_ok=True)
                futures.append(
                    executor.submit(self._download, remote_filename, dst,
                                    config["mandatory"])
                )
            for complete_ret in concurrent.futures.as_completed(futures):
                complete_ret.result()  # Raise exception if any

    def _handle_ddk_workspace(self) -> None:
        if not self.ddk_workspace:
            return
        self.ddk_workspace.mkdir(parents=True, exist_ok=True)

    def _handle_kleaf_repo(self) -> None:
        if not self.kleaf_repo:
            return
        self.kleaf_repo.mkdir(parents=True, exist_ok=True)
        self._sync_git_projects()
        self._populate_kleaf_repo_extra_files()

    def _handle_prebuilts(self) -> None:
        if not self.prebuilts_dir:
            return
        self.prebuilts_dir.mkdir(parents=True, exist_ok=True)
        if self._can_download_artifacts():
            self._download_prebuilts()

    def _sync_git_projects(self) -> None:
        """Populates kleaf_repo by adding and syncing Git projects."""
        if self.local:
            logging.info(
                "Skipped adding Git projects to kleaf_repo with --local.")
            # --local assumes the kernel source tree is complete.
            return
        if not self.kleaf_repo:
            logging.info(
                "Skipped adding Git projects because --kleaf_repo is "
                "unspecified"
            )
            return
        # repo root or git root, depending on the context
        superproject_root = self._maybe_init_superproject()

        project_paths = self._populate_kleaf_repo_manifest(superproject_root)
        self._modify_main_repo_manifest(superproject_root)
        self._repo_sync(superproject_root, project_paths)

    def _maybe_init_superproject(self) -> pathlib.Path:
        """Returns repo root or git root, depending on --superproject_tool.
        """
        match self.superproject_tool:
            case "repo":
                return self._find_repo_root()
            # TODO: For git, if --kleaf_repo not under git, run `git init`
        raise KleafProjectSetterError(
            f"Invalid value for --superproject_tool: {self.superproject_tool}")

    def _find_repo_root(self) -> pathlib.Path:
        """If --kleaf_repo is under a repo manifest, return repo root.

        Otherwise raise, because we cannot infer a sensible `--manifest-url`
        for `repo init`.
        """
        if not self.kleaf_repo:
            raise KleafProjectSetterError(
                "ERROR: _maybe_init_repo called without --kleaf_repo!")
        repo_root = self._find_repo(self.kleaf_repo)
        if repo_root:
            return repo_root

        raise KleafProjectSetterError(textwrap.dedent(f"""\
            ERROR: repo not initialized at or above {self.kleaf_repo}.
            Please set up a repo manifest project, then initialize it.
            For details, please visit
                https://gerrit.googlesource.com/git-repo/+/HEAD/README.md
            For example:
                cd {self._get_prospect_superproject_root()} && repo init -u ...
        """))

    @staticmethod
    def _find_repo(curdir: pathlib.Path) -> pathlib.Path | None:
        """Find repo installation."""
        while curdir.parent != curdir:  # is not root
            maybe_repo_main = curdir / ".repo"
            if maybe_repo_main.is_dir():
                return curdir
            curdir = curdir.parent
        return None

    def _get_prospect_superproject_root(self):
        """Returns a sensible default for superproject root."""
        if not self.kleaf_repo:
            raise KleafProjectSetterError(
                "ERROR: _get_prospect_superproject_root called without "
                "--kleaf_repo!")
        if (self.ddk_workspace and
                self.kleaf_repo.is_relative_to(self.ddk_workspace)):
            return self.ddk_workspace
        else:
            return self.kleaf_repo

    def _populate_kleaf_repo_manifest(self, superproject_root: pathlib.Path) \
        -> list[pathlib.Path]:
        """Populates .repo/manifests/kleaf.xml.

        Returns:
            list of Git project paths relative to repo root"""
        if not self.kleaf_repo:
            raise KleafProjectSetterError(
                "ERROR: _populate_kleaf_repo_manifest called without "
                "--kleaf_repo!")
        if not self.prebuilts_dir:
            # TODO: Support checking out full git sources without downloading
            #   GKI prebuilts
            logging.info("Skip checking out Kleaf projects without "
                         "--prebuilts_dir")
            return []

        # TODO: if not self.prebuilts_dir, groups should be None.
        groups = {"ddk", "ddk-external"}

        kleaf_repo_rel = self.kleaf_repo.relative_to(superproject_root)

        with open(superproject_root / f".repo/manifests/{_KLEAF_MANIFEST}") \
            as kleaf_manifest:
            return RepoManifestParser(
                project_prefix=kleaf_repo_rel,
                manifest=self._repo_manifest_of_build,
                groups = groups,
            ).write_transformed_dom(kleaf_manifest)

    def _modify_main_repo_manifest(self, superproject_root: pathlib.Path):
        # TODO: make sure comments in the original manifest is kept.
        # TODO: name of manifest is configurable in repo. Do we want to allow
        #   configuration of it?
        manifest_path = superproject_root / ".repo/manifests/default.xml"
        with open(manifest_path, "r+") as manifest:
            try:
                with xml.dom.minidom.parse(manifest) as dom:
                    root: xml.dom.minidom.Element = dom.documentElement
                    for include in root.getElementsByTagName("include"):
                        if include.getAttribute("name") == _KLEAF_MANIFEST:
                            return
                    include = dom.createElement("include")
                    include.setAttribute("name", _KLEAF_MANIFEST)
                    root.appendChild(include)

                    manifest.seek(0)
                    dom.writexml(manifest)
            except xml.parsers.expat.ExpatError as err:
                raise KleafProjectSetterError(
                    f"Unable to parse repo manifest {manifest_path}") from err

    def _repo_sync(self, superproject_root: pathlib.Path,
                   project_paths: list[pathlib.Path]):
        """Syncs project_paths below superproject_root."""
        if self.dryrun_checkout:
            logging.info("Skip repo sync because --dryrun_checkout")
            return
        subprocess_args = ["repo", "sync", "-c"]
        subprocess_args.extend(str(path) for path in project_paths)
        subprocess.check_call(subprocess_args, cwd=superproject_root)

    def _populate_kleaf_repo_extra_files(self) -> None:
        """Populates kleaf_repo by adding extra files"""
        if self.local:
            logging.info("Skipped populating kleaf_repo with --local.")
            # --local assumes the kernel source tree is complete.
            return
        if not self.kleaf_repo:
            logging.info(
                "Skipped populating --kleaf_repo because it is unspecified"
            )
            return
        if not self.prebuilts_dir:
            logging.info(
                "No prebuilts specified, skip populating %s", self.kleaf_repo
            )
            return
        self._extract_headers_archive(self.prebuilts_dir, self.kleaf_repo)

        build_config_constants = self.prebuilts_dir / "build.config.constants"
        if not build_config_constants.is_file():
            logging.warning(
                "%s is not a file, skip copying", build_config_constants
            )
            return
        shutil.copy(
            build_config_constants,
            self.kleaf_repo / "common/build.config.constants",
        )
        if not (self.kleaf_repo / "common/BUILD.bazel").is_file():
            (self.kleaf_repo / "common/BUILD.bazel").write_text("")

    @staticmethod
    def _extract_headers_archive(
        prebuilts_dir: pathlib.Path, kleaf_repo: pathlib.Path
    ):
        """Extracts DDK headers archive from prebuilts_dir into kleaf_repo"""
        # TODO: This should be target-specific. The name of the output is
        # currently (2024-05-16) defined by common/BUILD.bazel, but it may
        # change in the future.
        header_archives = list(
            prebuilts_dir.glob("*_ddk_headers_archive.tar.gz")
        )
        if not header_archives:
            logging.warning(
                "No _ddk_headers_archive.tar.gz found in %s, "
                "skipping header extraction.",
                prebuilts_dir,
            )
            return
        if len(header_archives) > 1:
            raise KleafProjectSetterError(
                "Multiple _ddk_headers_archive.tar.gz found in "
                f"{prebuilts_dir}: {header_archives}"
            )
        logging.info(
            "Extracting header archive %s to %s", header_archives[0], kleaf_repo
        )
        with tarfile.open(header_archives[0]) as tar:
            tar.extractall(kleaf_repo)

    def _run(self) -> None:
        self._symlink_tools_bazel()
        self._generate_module_bazel()
        self._generate_bazelrc()

    def run(self) -> None:
        self._handle_ddk_workspace()
        self._download_meta_files()
        self._handle_prebuilts()
        self._handle_kleaf_repo()
        self._run()


@dataclasses.dataclass
class RepoManifestParser:
    """Parses the repo manifest from a build."""
    manifest: str
    project_prefix: pathlib.Path

    # If None, add all projects. If a set, only add projects that matches
    # any of these groups. If an empty set, no project is added.
    groups: set[str] | None

    def write_transformed_dom(self, file: TextIO) \
        -> list[pathlib.Path]:
        """Transforms manifest from the build and write result to file.

        Returns:
            list of Git project paths relative to repo root
        """
        try:
            with xml.dom.minidom.parse(self.manifest) as dom:
                project_paths = self._transform_dom(dom)
                dom.writexml(file)
                return project_paths
        except xml.parsers.expat.ExpatError as err:
            raise KleafProjectSetterError("Unable to parse repo manifest") \
                from err

    def _transform_dom(self, dom: xml.dom.minidom.Document) \
        -> list[pathlib.Path]:
        """Transforms manifest from the build.

        - Append project_prefix to each project.
        - Filter out projects of mismatching groups
        - Drop elements that may conflict with the main manifest

        Returns:
            list of Git project paths relative to repo root
        """
        root: xml.dom.minidom.Element = dom.documentElement
        projects = root.getElementsByTagName("project")
        defaults = self._parse_repo_manifest_defaults(root)
        project_paths = []
        for project in projects:
            if not self._match_group(project):
                root.removeChild(project).unlink()
                continue

            # https://gerrit.googlesource.com/git-repo/+/master/docs/manifest-format.md#element-project
            orig_path_below_repo = pathlib.Path(project.getAttribute("path") or
                                                project.getAttribute("name"))
            path_below_repo = self.project_prefix / orig_path_below_repo
            project_paths.append(path_below_repo)
            project.setAttribute("path", str(path_below_repo))
            # TODO filter non-DDK projects if necessary
            for key, value in defaults:
                if not project.hasAttribute(key):
                    project.setAttribute(key, value)

        # Avoid <superproject> and <default> in Kleaf manifest conflicting with
        # the one in main manifest
        for superproject in root.getElementsByTagName("superproject"):
            root.removeChild(superproject).unlink()
        for default_element in root.getElementsByTagName("default"):
            root.removeChild(default_element).unlink()
        return project_paths

    def _match_group(self, project: xml.dom.minidom.Element):
        """Returns true if project matches any of groups."""
        if self.groups is None:
            return True
        project_groups = re.split(r",| ", project.getAttribute("groups"))
        return bool(set(project_groups) & self.groups)

    def _parse_repo_manifest_defaults(self, root: xml.dom.minidom.Element):
        """Parses <default> in a repo manifest. """
        ret = dict[str, str]()
        for default_element in root.getElementsByTagName("default"):
            attrs = default_element.attributes
            for index in range(attrs.length):
                attr = attrs.item(index)
                assert isinstance(attr, xml.dom.minidom.Attr)
                ret[attr.name] = attr.value
        return ret


if __name__ == "__main__":

    def abs_path(path_string: str) -> pathlib.Path | None:
        path = pathlib.Path(path_string)
        if not path.is_absolute():
            raise ValueError(f"{path} is not an absolute path.")
        return path

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--build_id",
        type=str,
        help="the build id to download the build for, e.g. 6148204",
        default=None,
    )
    parser.add_argument(
        "--build_target",
        type=str,
        help='the build target to download, e.g. "kernel_aarch64"',
        default="kernel_aarch64",
    )
    parser.add_argument(
        "--ddk_workspace",
        help="Absolute path to DDK workspace root.",
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--local",
        help="Whether to use a local source tree containing Kleaf.",
        action="store_true",
    )
    parser.add_argument(
        "--kleaf_repo",
        help="Absolute path to Kleaf's repo dir.",
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--prebuilts_dir",
        help=(
            "Absolute path to local GKI prebuilts. Usually, it is located"
            " within workspace."
        ),
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--url_fmt",
        help="URL format endpoint for CI downloads.",
        default=None,
    )
    parser.add_argument(
        "--superproject_tool",
        help="""Tool to manage the superproject.

            Currently only `repo` is supported. This requires repo to be
            installed on your machine.
        """,
        choices=["repo"],
        default="repo",
    )
    parser.add_argument(
        "--dryrun_checkout",
        help="Do not sync Git projects for Kleaf tooling.",
        action="store_true",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")
    # Validate pre-condition.
    if args.local and not args.kleaf_repo:
        parser.error("--local requires --kleaf_repo.")
    try:
        KleafProjectSetter(**vars(args)).run()
    except KleafProjectSetterError as e:
        logging.error(e, exc_info=e)
        sys.exit(1)
