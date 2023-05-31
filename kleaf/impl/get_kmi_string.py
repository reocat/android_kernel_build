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

"""Extracts the string representing the KMI from the kernel release string.

$ python3 get_kmi_string.py 5.15.123-android14-6-something
5.15-android14-6

$ python3 get_kmi_string.py --keep_sublevel 5.15.123-android14-6-something
5.15.123-android14-6

$ python3 get_kmi_string.py 6.1.55-mainline
# prints nothing
"""

import argparse
import logging
import re
import sys


def get_kmi_string(kernel_release: str, keep_sublevel: bool) -> str | None:
    """Extracts the string representing the KMI from the kernel release string.

    >>> get_kmi_string("5.15.123-android14-6", True)
    '5.15.123-android14-6'

    >>> get_kmi_string("5.15.123-android14-6-something", True)
    '5.15.123-android14-6'

    >>> get_kmi_string("5.15.123-android14-6", False)
    '5.15-android14-6'

    >>> get_kmi_string("5.15.123-android14-6-something", False)
    '5.15-android14-6'

    >>> get_kmi_string("6.1.55-mainline", False)

    >>> get_kmi_string("6.1.55-mainline-something", False)
    """
    if "mainline" in kernel_release.split("-"):
        return None
    pat = re.compile(r"^(\d+[.]\d+)[.](\d+)-(android\d+-\d+)(?:-.*)?$")
    mo = pat.match(kernel_release)
    if not mo:
        logging.error("Unrecognized %s", kernel_release)
        sys.exit(1)
    version_patch_level = mo.group(1)
    sublevel = mo.group(2)
    android_release_kmi_generation = mo.group(3)

    if keep_sublevel:
        return f"{version_patch_level}.{sublevel}-{android_release_kmi_generation}"

    return f"{version_patch_level}-{android_release_kmi_generation}"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep_sublevel", action="store_true")
    parser.add_argument("kernel_release")
    logging.basicConfig(stream=sys.stderr,
                        level=logging.WARNING,
                        format="%(levelname)s: %(message)s")
    result = get_kmi_string(**vars(parser.parse_args()))
    if result:
        print(result)
