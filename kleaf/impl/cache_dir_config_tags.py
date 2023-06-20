# Copyright (C) 2023 The Android Open Source Project
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

"""Utility to create / reconcile the identity file for a subdirectory under --cache_dir."""

import argparse
import json
import pathlib
import sys
from typing import TextIO


def load_json(path: pathlib.Path):
    with open(path, "r") as fp:
        try:
            return json.load(fp)
        except json.JSONDecodeError as e:
            print(f"ERROR: Failed to load {path}: {e}", file=sys.stderr)
            sys.exit(1)


def dump_json(object, fp):
    """Dumps object to file-like object fp."""
    json.dump(object, fp, sort_keys=True, indent=4)


def comment_json(object, fp):
    """Dumps object to file-like object fp, with each line prefixed with #."""
    lines = json.dumps(object, sort_keys=True, indent=4).splitlines()
    lines = [f"# {line}" for line in lines]
    fp.write("\n".join(lines))


def main(
        base: pathlib.Path,
        target: str | None,
        defconfig_fragments: list[pathlib.Path] | None,
        dest: pathlib.Path,
        comment: bool,
):
    config_tags = load_json(base)

    if target is not None:
        config_tags["_target"] = target

    if defconfig_fragments is not None:
        if "_defconfig_fragments" in config_tags:
            print(f"ERROR: {base} already has _defconfig_fragments!",
                  file=sys.stderr)
            sys.exit(1)

        config_tags["_defconfig_fragments"] = [
            str(path) for path in defconfig_fragments]

    if comment:
        write_json = comment_json
    else:
        write_json = dump_json

    if dest.is_file():
        existing_config_tags = load_json(dest)
        if existing_config_tags != config_tags:
            print(f"ERROR: Collision detected in {dest}", file=sys.stderr)
            print(f"Original: ", file=sys.stderr)
            write_json(existing_config_tags, sys.stderr)
            print(file=sys.stderr)
            print(f"New: ", file=sys.stderr)
            write_json(config_tags, sys.stderr)
            print(file=sys.stderr)
            sys.exit(1)
    else:
        with open(dest, "w") as dest_file:
            write_json(config_tags, dest_file)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base", type=pathlib.Path,
        required=True,
        help="source kleaf_config_tags.json",
    )
    parser.add_argument(
        "--target", help="If set, add label of target to the result")
    parser.add_argument("--defconfig_fragments", nargs="*",
                        type=pathlib.Path, default=None,
                        help="If set, add defconfig fragments to result")
    parser.add_argument(
        "--dest", type=pathlib.Path,
        required=True,
        help="output kleaf_config_tags.json",
    )
    parser.add_argument("--comment", action="store_true", default=False)
    args = parser.parse_args()

    main(**vars(args))
