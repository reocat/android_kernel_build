#!/usr/bin/env python3
#
# Copyright (C) 2020 The Android Open Source Project
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

import configparser
import sys


TRACE_POINT = '__tracepoint_'
TRACE_ITER = '__traceiter_'


def main():
    """Convert a KMI symbol list in libabigail format to a raw list."""
    if sys.stdin.isatty():
        print('ERROR: missing KMI symbol list on the standard input')
        return 1

    sl = configparser.ConfigParser(allow_no_value=True, strict=False)
    sl.optionxform = str
    sl.read_file(sys.stdin)

    ksyms = set()
    for section in (s for s in sl.sections() if s.endswith(('whitelist',
                                                            'symbol_list'))):
        ksyms.update(sl[section])

    # Check for consistency
    for symbol in ksyms:
        if not symbol.startswith(TRACE_POINT) and not symbol.startswith(TRACE_ITER):
            continue
        if symbol.startswith(TRACE_POINT):
            other = symbol.replace(TRACE_POINT, TRACE_ITER)
            if other not in ksyms:
                print('ERROR: Missing symbol: ', other, file=sys.stderr)
                return 1
        if symbol.startswith(TRACE_ITER):
            other = symbol.replace(TRACE_ITER, TRACE_POINT)
            if other not in ksyms:
                print('ERROR: Missing symbol: ', other, file=sys.stderr)
                return 1

    print('\n'.join(sorted(ksyms)))


if __name__ == '__main__':
    sys.exit(main())
