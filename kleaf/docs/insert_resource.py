#!/usr/bin/env python3

import argparse
import io
import os

MAGIC = "<!--RESOURCE_EMBED_HINT-->\n"

def main(infile: io.IOBase, outfile: io.IOBase, resources: list[str]):
    """Embed resources into infile, assuming that resources are a list of files that
    are complete HTMLs. Does not protect from HTML injection.
    """
    inlines = infile.readlines()
    magic = inlines.index(MAGIC)

    outlines = inlines[:magic + 1]
    for resource_name in resources:
        outlines.append('<div hidden id="{}">\n'.format(os.path.basename(resource_name)))
        with open(resource_name) as resource:
            outlines += resource.readlines()
        outlines.append('</div>\n')
    outlines += inlines[magic + 1:]

    outfile.writelines(outlines)

if __name__ == '__main__':
  parser = argparse.ArgumentParser(description=main.__doc__)
  parser.add_argument("--infile", required=True, type=argparse.FileType('r'), help="input file")
  parser.add_argument("--outfile", required=True, type=argparse.FileType('w'), help="output file")
  parser.add_argument("--resources", nargs='*', help="resource files")
  args = parser.parse_args()
  main(**vars(args))
