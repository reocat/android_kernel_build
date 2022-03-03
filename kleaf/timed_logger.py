#!/usr/bin/env python3

import sys
import time

start = time.monotonic()

while True:
    line = sys.stdin.readline()
    if line:
        sys.stdout.write("{:8.2f}: {}".format(time.monotonic() - start, line))
        sys.stdout.flush()
    else:
        break
