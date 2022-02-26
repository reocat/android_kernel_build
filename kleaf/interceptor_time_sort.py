#!/usr/bin/python3
import collections

import sys


class Line(object):
    def __init__(self, *args):
        self.parent_pid = args[0]
        self.exec_pid = args[1]
        self.start = int(args[2])
        self.stop = int(args[3])
        self.cmd = args[4]
        self.children = args[5] if len(args) > 5 else []


# exec_pid -> Line[]
lines_dict = collections.defaultdict(list)
with open(sys.argv[1]) as f:
    for line in f.readlines():
        line = line.strip()
        tup = line.split(" ", maxsplit=4)
        obj = Line(*tup)
        lines_dict[obj.exec_pid].append(obj)

# parent_pid -> Line[]
roots = collections.defaultdict(list)
for lines in lines_dict.values():
    for line in lines:
        parents = lines_dict.get(line.parent_pid)
        if parents:
            parents[0].children.append(line)
        else:
            roots[line.parent_pid].append(line)

# parent_pid -> fake parent Line object
roots = {parent_pid: Line(0, parent_pid, min(children, key=lambda child: child.start).start,
                          max(children, key=lambda child: child.stop).stop, "",
                          sorted(children, key=lambda child: child.start)) for
         parent_pid, children in roots.items()}

offset = min(roots.values(), key=lambda root_line: root_line.start).start


def print_line(line, indent=0):
    print("{}P={} E={} {:.1f}~{:.1f} ({:.1f}s) {}".format(" " * indent, line.parent_pid, line.exec_pid,
                                               (line.start - offset) / 1000000,
                                               (line.stop - offset) / 1000000,
                                               (line.stop - line.start) / 1000000,
                                               line.cmd))
    for child in line.children:
        print_line(child, indent=indent + 1)

for root_line in roots.values():
    print_line(root_line)
