#!/usr/bin/env python3
#
# Copyright (C) 2019-2023 The Android Open Source Project
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
#

import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--linux-tree", required=True)
    parser.add_argument("--vmlinux", default=None)
    parser.add_argument("--abi-tool", default=None)
    parser.add_argument("--out-file", default=None)
    parser.add_argument("--kmi-symbol-list", "--kmi-whitelist", default=None)

    args = parser.parse_args()
    filename = args.out_file or os.path.join(args.linux_tree, "abi.xml")
    with open(filename, "w") as out:
        out.write("<!-- dump_abi is no longer functional, use stg instead -->\n")
        out.write("<abi-corpus/>\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
