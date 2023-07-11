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

"""Kleaf SBOM generator: Generate SBOM for kernel build.

Inputs:
1. --version: The android kernel build version string.
              example: 5.15.110-android14-11-00098-gbdd2312e95c7-ab10365441
2. --dist_dir: Output dir where all the kernel build artifacts are.
              example: out/kernel_aarch64/dist
3. --output_file: File where SBOM should be written.
              example: kernel_sbom.spdx.json

Examples:

    # Generate SBOM after a kernel build with dist.
    build/kernel/kleaf/kernel_sbom.py \
      --version "5.15.110-android14-11-00098-gbdd2312e95c7-ab10365441" \
      --dist_dir "out/kernel_aarch64/dist" \
      --output_file "kernel_sbom.spdx.json"
"""

import argparse
from dataclasses import dataclass
import datetime
import glob
import hashlib
import json
import os
from typing import Any


_SPDX_VERSION = "SPDX-2.3"
_DATA_LICENSE = "CC0-1.0"
_GOOGLE_ORGANIZATION_NAME = "Google"
_LINUX_ORGANIZATION_NAME = "The Linux Kernel Organization"
_LINUX_UPSTREAM_WEBSITE = "kernel.org"
_NAMESPACE_PREFIX = "https://www.google.com/sbom/spdx/android/kernel/"
_MAIN_PACKAGE_NAME = "kernel"
_SOURCE_CODE_PACKAGE_NAME = "KernelSourceCode"
_LINUX_UPSTREAM_PACKAGE_NAME = "LinuxUpstreamPackage"
_GENERATED_FROM_RELATIONSHIP = "GENERATED_FROM"
_VARIANT_OF_RELATIONSHIP = "VARIANT_OF"
_SPDX_REF = "SPDXRef"


@dataclass
class File:
  id: str
  name: str
  path: str
  checksum: str


class KernelSbom:
  def __init__(self,
               android_kernel_version: str,
               file_list: list[str]):
    self.android_kernel_version = android_kernel_version
    self.upstream_kernel_version = android_kernel_version.split('-')[0]
    self._files = []
    for file_path in file_list:
      basename = os.path.basename(file_path)
      self._files.append(File(id=f"{_SPDX_REF}-{basename}",
                              name=basename,
                              path=file_path,
                              checksum=self._checksum(file_path)))
    self._sbom_doc = self._generate_sbom()

  def _checksum(self, file_path: str) -> str:
    h = hashlib.sha1()
    if os.path.islink(file_path):
      h.update(os.readlink(file_path).encode('utf-8'))
    else:
      with open(file_path, 'rb') as f:
        h.update(f.read())
    return f'SHA1: {h.hexdigest()}'


  def _generate_package_verification_code(self, files: list[File]) -> str:
    checksums = [f.checksum for f in files]
    checksums.sort()
    h = hashlib.sha1()
    h.update(''.join(checksums).encode(encoding='utf-8'))
    return h.hexdigest()


  def _generate_doc_headers(self) -> dict[str: Any]:
    timestamp = datetime.datetime.now(
        tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    namespace = os.path.join(_NAMESPACE_PREFIX, self.android_kernel_version)
    headers = {
        "spdxVersion": _SPDX_VERSION,
        "dataLicense": _DATA_LICENSE,
        "SPDXID": f"{_SPDX_REF}-DOCUMENT",
        "name": self.android_kernel_version,
        "documentNamespace": namespace,
        "creationInfo": {
            "creators": [
                f"Organization: {_GOOGLE_ORGANIZATION_NAME}"
            ],
            "created": timestamp
        },
        "documentDescribes": [
            f"SPDXRef-{_MAIN_PACKAGE_NAME}"
        ]}
    return headers


  def _generate_package_dict(
      self,
      version: str,
      package_name: str,
      file_list: list[File] = None,
      organization: str = _GOOGLE_ORGANIZATION_NAME,
      download_location: str = None,
      ) -> dict[str: Any]:
    package_dict = {
        "name": package_name,
              "SPDXID": f"{_SPDX_REF}-{package_name}",
              "downloadLocation": download_location,
              "filesAnalyzed": False,
              "versionInfo": version,
              "supplier": f"Organization: {organization}",
    }
    if file_list is not None:
      package_dict["hasFiles"] = [file.name for file in file_list]
      verification_hash = self._generate_package_verification_code(file_list)
      package_dict["packageVerificationCode"] = {
          "packageVerificationCodeValue": verification_hash
      }
    return package_dict

  def _generate_file_dict(self, file: File) -> dict[str: Any]:
    return {
        "fileName": file.name,
        "SPDXID": file.id,
        "checksums": [
            {
            "algorithm": "SHA1",
            "checksumValue": file.checksum,
            },
        ]
    }

  def _generate_relationship_dict(
      self,
      element: str,
      related_element: str,
      relationship_type: str
      ) -> dict[str: Any]:
    return {
        "spdxElementId": element,
        "relatedSpdxElement": related_element,
        "relationshipType": relationship_type,
    }

  def _generate_sbom(self) -> dict[str: Any]:
    sbom = {}
    packages = []
    packages.append(self._generate_package_dict(self.android_kernel_version,
                                          _MAIN_PACKAGE_NAME,
                                          self._files))
    packages.append(self._generate_package_dict(self.android_kernel_version,
                                          _SOURCE_CODE_PACKAGE_NAME))
    packages.append(self._generate_package_dict(self.upstream_kernel_version,
                                          _LINUX_UPSTREAM_PACKAGE_NAME,
                                          None,
                                          _LINUX_ORGANIZATION_NAME,
                                          _LINUX_UPSTREAM_WEBSITE))
    sbom.update(self._generate_doc_headers())
    sbom["packages"] = packages
    sbom["files"] = [self._generate_file_dict(f) for f in self._files]

    relationships = []
    relationships.append(
        self._generate_relationship_dict(
            f"{_SPDX_REF}-{_MAIN_PACKAGE_NAME}",
            f"{_SPDX_REF}-{_SOURCE_CODE_PACKAGE_NAME}",
            _GENERATED_FROM_RELATIONSHIP)
        )
    relationships.append(
        self._generate_relationship_dict(
            f"{_SPDX_REF}-{_SOURCE_CODE_PACKAGE_NAME}",
            f"{_SPDX_REF}-{_LINUX_UPSTREAM_PACKAGE_NAME}",
            _VARIANT_OF_RELATIONSHIP)
        )
    for f in self._files:
      relationships.append(
          self._generate_relationship_dict(
              f.id,
              f"{_SPDX_REF}-{_SOURCE_CODE_PACKAGE_NAME}",
              _GENERATED_FROM_RELATIONSHIP)
          )

    sbom["relationships"] = relationships
    return sbom

  def write_sbom_file(self, output_path: str):
    with open(output_path, 'w', encoding="utf-8") as output_file:
      output_file.write(json.dumps(self._sbom_doc, indent=4))

  def print_sbom(self, log_func):
    log_func(json.dumps(self._sbom_doc, indent=4))


def get_args():
  parser = argparse.ArgumentParser()
  parser.add_argument('--output_file',
                      required=True,
                      help='The generated SBOM file in SPDX format.')
  parser.add_argument('--dist_dir',
                      required=True,
                      help='Directory containing generated artifacts.')
  parser.add_argument('--version',
                      required=True,
                      help='The android kernel version.')
  return parser.parse_args()


def get_file_list(dist_dir: str) -> list[str]:
  path = os.path.join(dist_dir, "**")
  recursive_list = glob.glob(path, recursive = True)
  files = [f for f in recursive_list if os.path.isfile(f)]
  return files


def main():
  global args
  args = get_args()
  files = get_file_list(args.dist_dir)
  sbom = KernelSbom(args.version, files)
  sbom.write_sbom_file(args.output_file)


if __name__ == '__main__':
  main()
