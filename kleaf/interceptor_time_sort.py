#!/usr/bin/python3
import sys
l = []
with open(sys.argv[1]) as f:
    for line in f.readlines():
        line = line.strip()
        time, command = line.split(" ", maxsplit=1)
        l.append((time, command))

l = sorted(l, key = lambda tuple: int(tuple[0]), reverse=True)
for time, command in l:
    print(time, command)
