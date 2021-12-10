#!/usr/bin/env python3

"""
Generate a kconfig file.
"""

import argparse
import json
import sys

def kconfig_gen(name, type, out, prompt="", helpstr="", deps=()):
    out.write("config {}\n".format(name))
    if prompt:
        out.write("\t{type} {prompt}\n".format(type=type, prompt=json.dumps(prompt)))
    else:
        out.write("\t{}\n".format(type))
    for dep in deps:
        out.write("\tdepends on {}\n".format(dep))
    if helpstr:
        out.write("\thelp\n")
        for line in helpstr.split("\n"):
            out.write("\t {}\n".format(line))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--type", required=True)
    parser.add_argument("--prompt", default="")
    parser.add_argument("--helpstr", default="")
    parser.add_argument("--deps", nargs="*")
    parser.add_argument("--out", type=argparse.FileType('w'),
                        default=sys.stdout)
    kconfig_gen(**vars(parser.parse_args()))
