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
import json
import pathlib
import sys

import symbol_extraction


def find_binaries(
    directory: pathlib.Path,
) -> (pathlib.Path | None, list[pathlib.Path]):
    """Locates vmlinux and kernel modules (*.ko)."""
    vmlinux = list(directory.glob("**/vmlinux"))
    modules = list(directory.glob("**/*.ko"))
    # TODO: Error out if multiple vmlinux are found.
    if not vmlinux:
        return None, modules
    return vmlinux[0], modules


def extract_exports_map(
    blobs: list[pathlib.Path],
) -> dict[pathlib.Path, list[str]]:
    """Extracts the ksymtab exported symbols for a list of objects."""
    return {
        pathlib.Path(blob).name: symbol_extraction.extract_exported_symbols(
            blob
        )
        for blob in blobs
    }


def extract_undefined_symbols_multiple(
    modules: list[pathlib.Path],
) -> dict[pathlib.Path, list[str]]:
    """Extracts undefined symbols from a list of module files."""
    return {
        pathlib.Path(module).name: symbol_extraction.extract_undefined_symbols(
            module
        )
        for module in modules
    }


def create_graph(
    undefined_symbols: dict[pathlib.Path, list[str]],
    exported_symbols: dict[pathlib.Path, list[str]],
    output: pathlib.Path,
):
    "Creates a best effort dependency graph from symbol relationships."
    idx = dict()
    symbol_to_module = dict()
    adjacency_list = list()

    # Map symbol exported to module which exposes.
    for module, exported in exported_symbols.items():
        if not module in idx:
            idx[module] = len(idx)
            adjacency_list.append(
                {"name": module.removesuffix(".ko"), "dependents": dict()}
            )
        exporter = idx.get(module)
        for symbol in exported:
            symbol_to_module[symbol] = exporter

    # Update the adjacency_list based on the links created by the undefined symbols.
    for module, symbols in undefined_symbols.items():
        to_id = idx.get(module)
        for symbol in symbols:
            if symbol not in symbol_to_module:
                continue
            from_id = symbol_to_module[symbol]
            adjacency_list[from_id]["dependents"][to_id] = ""

    # Print the graph.
    output.write_text(json.dumps(adjacency_list), encoding="utf-8")


def main():
    """Extracts the required symbols for a directory full of kernel modules."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "directory",
        type=pathlib.Path,
        help="the directory to search for kernel binaries",
    )
    parser.add_argument(
        "output",
        type=pathlib.Path,
        help="Path for storing the output",
    )
    args = parser.parse_args()

    if not args.directory.is_dir():
        print(f"Expected a directory with binaries, but got {args.directory}")
        return 1

    # Locate the Kernel Binaries.
    vmlinux, modules = find_binaries(args.directory)

    # Extract undefined symbols and exported modules.
    undefined_symbols = extract_undefined_symbols_multiple(modules)
    exported_symbols = extract_exports_map([vmlinux] + modules)

    # Create a dependency graph.
    create_graph(undefined_symbols, exported_symbols, args.output)


if __name__ == "__main__":
    sys.exit(main())
