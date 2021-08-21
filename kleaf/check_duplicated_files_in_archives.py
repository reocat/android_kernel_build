#!/usr/bin/env python3

import argparse
import collections
import pathlib
import subprocess


def sanitize(line: str):
  line = line.strip()
  # If the command to create the archive was
  #   tar cvf foo.tar.gz -C directory .
  # then lines may start with "./". Resolve them properly.
  return str(pathlib.PurePosixPath(line))


def list_files(archive: list):
  output = subprocess.check_output(["tar", "tf", archive], text=True)
  return [sanitize(line) for line in output.strip().split("\n")]


def main(archives: list):
  """
  Check that when extracting each archive to the same directory, files won't be
  overwritten.

  This is a semi-replacement of the -k option in GNU tar.
  """
  archive_files = {arc: list_files(arc) for arc in archives}
  reverse_dict = collections.defaultdict(list)
  for archive, files in archive_files.items():
    for file in files:
      reverse_dict[file].append(archive)
  duplicated = {file: archives for file, archives in reverse_dict.items() if
                len(archives) > 1}
  if duplicated:
    msg = "\n".join(
        f"File {file} appeared in {len(archives)} archives:\n  " + "\n  ".join(
          archives) for file, archives in duplicated.items())
    raise Exception(f"Multiple archives contain the same files.\n{msg}")


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=main.__doc__)
  parser.add_argument("archives", nargs="*",
                      help="A list of tar archives to check")
  args = parser.parse_args()
  main(**vars(args))
