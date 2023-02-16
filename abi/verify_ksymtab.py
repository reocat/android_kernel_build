#!/usr/bin/env python3
#
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
#
"""Verify every symbol in symbol list is exported in ksymtab.

Usage:

   KMI_STRICT_MODE_OBJECTS: Environement variable with objects whose
                            exports should be consider to generate
                            ksymtab for verification against KMI symbol
                            list defaults to vmlinux.
   verify_ksymtab.py [-h] --raw-kmi-symbol-list RAW_KMI_SYMBOL_LIST
                          --module-symvers-file MODULE_SYMVERS_FILE
"""

import argparse
import os
import sys


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument(
      "--raw-kmi-symbol-list",
      required=True,
      help="Symbol list",
  )

  parser.add_argument(
      "--module-symvers-file",
      required=True,
      help="Module.symvers file to check ksymtab",
  )

  args = parser.parse_args()

  # Objects whose exports to consider when building ksymtab for verification
  objects = os.environ.get("KMI_STRICT_MODE_OBJECTS", "vmlinux").split()

  # Parse Module.symvers, and ignore non-exported and vendor-specific symbols
  ksymtab_symbols = []
  with open(args.module_symvers_file) as module_symvers_file:
    for line in module_symvers_file:
      ksym = line.strip().split("\t")
      # 1=symbol name; 2=object name; 3=export type
      if not ksym[3].startswith("EXPORT_SYMBOL") or ksym[2] not in objects:
        continue
      ksymtab_symbols.append(ksym[1])

  # List of symbols defined in the raw_kmi_symbol_list with newline stripped
  kmi_symbols = []
  with open(args.raw_kmi_symbol_list) as raw_kmi_symbol_list_file:
    kmi_symbols = [
        symbol.strip() for symbol in raw_kmi_symbol_list_file.readlines()
    ]

  # Set difference to get elements in symbol list but not in ksymtab
  missing_ksymtab_symbols = set(kmi_symbols) - set(ksymtab_symbols)
  if missing_ksymtab_symbols:
    print("Symbols missing from the ksymtab:")
    for symbol in sorted(missing_ksymtab_symbols):
      print(f"  {symbol}")
    return 1

  return 0


if __name__ == "__main__":
  sys.exit(main())
