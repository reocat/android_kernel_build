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

"""Parses the repo manifest from a build."""

import dataclasses
import pathlib
import re
import xml.dom.minidom
import xml.parsers.expat
from typing import TextIO

from init.init_errors import KleafProjectSetterError

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
            with xml.dom.minidom.parseString(self.manifest) as dom:
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
            for key, value in defaults.items():
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

