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

"""Wrapper for repo operations."""

import dataclasses
import logging
import pathlib
import subprocess
import textwrap
import xml.dom.minidom
import xml.parsers.expat

from init.init_errors import KleafProjectSetterError
from init.repo_manifest_parser import RepoManifestParser


_KLEAF_MANIFEST = "kleaf.xml"


@dataclasses.dataclass
class RepoWrapper:
    """Wrapper for repo operations."""

    kleaf_repo: pathlib.Path
    prebuilts_dir: pathlib.Path | None
    ddk_workspace: pathlib.Path | None
    repo_manifest_of_build: str | None
    dryrun_checkout: bool

    def sync(self) -> None:
        """Populates kleaf_repo by adding and syncing Git projects."""
        superproject_root = self._find_repo_root()

        project_paths = self._populate_kleaf_repo_manifest(superproject_root)
        self._modify_main_repo_manifest(superproject_root)
        self._repo_sync(superproject_root, project_paths)

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
        if not self.repo_manifest_of_build:
            logging.warning(
                "Unable to infer the list of projects from repo manifest "
                "because there is no repo manifest")
            return []

        # TODO: if not self.prebuilts_dir, groups should be None.
        groups = {"ddk", "ddk-external"}

        kleaf_repo_rel = self.kleaf_repo.relative_to(superproject_root)

        with open(superproject_root / f".repo/manifests/{_KLEAF_MANIFEST}") \
                as kleaf_manifest:
            return RepoManifestParser(
                project_prefix=kleaf_repo_rel,
                manifest=self.repo_manifest_of_build,
                groups=groups,
            ).write_transformed_dom(kleaf_manifest)

    def _modify_main_repo_manifest(self, superproject_root: pathlib.Path):
        # TODO: make sure comments in the original manifest is kept.
        # TODO: name of manifest "default" is configurable in repo. Do we want
        #   to allow configuration of it?
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
