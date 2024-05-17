#!/usr/bin/env python3
#
# Copyright (C) 2024 The Android Open Source Project
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
# Utility function to provide a best effort dependency graph.

import argparse
import os
import pathlib
import sys

import symbol_extraction


def find_binaries(directory):
    """Locates vmlinux and kernel modules (*.ko)."""
    vmlinux = None
    modules = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".ko"):
                modules.append(os.path.join(root, file))
            elif file == "vmlinux":
                vmlinux = os.path.join(root, file)
    return vmlinux, modules


def extract_exports_map(blobs):
    """Extracts the ksymtab exported symbols for a list of objects."""
    return {
        os.path.basename(blob): sorted(
            symbol_extraction.extract_exported_symbols(blob)
        )
        for blob in blobs
    }


def extract_undefined_symbols_multiple(modules):
    """Extracts undefined symbols from a list of module files."""
    result = {}
    for module in sorted(modules):
        result[os.path.basename(module)] = sorted(
            symbol_extraction.extract_undefined_symbols(module)
        )

    return result


def create_graphviz(modules, adjacency_list, output):
    content = ["digraph {"]
    content.append(
        '\tstylesheet = "/frameworks/g3doc/includes/graphviz-style.css"'
    )
    for from_id, neighbors in enumerate(adjacency_list):
        if modules[from_id] == "vmlinux":
            continue
        for neighbor in neighbors:
            content.append(f'\t"{modules[from_id]}" -> "{modules[neighbor]}"')
    content.append("}")
    out = pathlib.Path(output)
    out.write_text("\n".join(content), encoding="utf-8")


def process_graph(symbols, exports, output):
    idx = dict()
    symbol_to_module = dict()
    adjacency_list = list()
    modules = list()

    # Map symbol exported to module which exposes.
    for module, exported in exports.items():
        if not module in idx:
            idx[module] = len(idx)
            adjacency_list.append(set())
            modules.append(module)
        exporter = idx.get(module)
        for symbol in exported:
            symbol_to_module[symbol] = exporter

    # Update the adjacency_list based on the links created by the undefined symbols.
    for module, undefined in symbols.items():
        to_id = idx.get(module)
        for symbol in undefined:
            from_id = symbol_to_module[symbol]
            adjacency_list[from_id].add(to_id)

    # Draw the dependencies.
    create_graphviz(modules, adjacency_list, output)


def main():
    """Extracts the required symbols for a directory full of kernel modules."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "directory",
        nargs="?",
        default=os.getcwd(),
        help="the directory to search for kernel binaries",
    )
    parser.add_argument("--output", help="Where to store the output")

    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Expected a directory with binaries, but got {args.directory}")
        return 1

    # Locate the Kernel Binaries
    vmlinux, modules = find_binaries(args.directory)

    symbols = extract_undefined_symbols_multiple(modules)
    exports = extract_exports_map([vmlinux] + modules)
    process_graph(symbols, exports, args.output)


if __name__ == "__main__":
    sys.exit(main())
