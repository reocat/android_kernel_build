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
# Utility function to create a visualization graph using dot language.

import argparse
import hashlib
import pathlib
import sys


def create_graphviz(
    modules: list[str],
    adjacency_list: list[set],
    output: pathlib.Path,
    colors: bool,
):
    "Creates a diagram to display a graph using dot language."
    content = ["digraph {"]
    content.extend([
        "\tgraph [rankdir=LR, splines=ortho];",
        "\tnode [color=steelblue, shape=plaintext];",
        "\tedge [arrowhead=odot, color=olive];",
    ])
    for from_id, neighbors in enumerate(adjacency_list):
        # vmlinux is dependency for most of the nodes so skip it.
        if modules[from_id] == "vmlinux":
            continue
        # Skip nodes without dependants.
        if not neighbors:
            # print(f"Skipping leaf module {modules[from_id]}")
            continue
        edges = []
        for neighbor in neighbors:
            edges.append(f'"{modules[neighbor]}"')
        edge_str = ",".join(edges)
        # Customize edge colors.
        edge_color = ""
        if colors:
            h = hashlib.shake_256(edge_str.encode())
            edge_color = f' [color="  # {h.hexdigest(3)}"]'
        content.append(f'\t"{modules[from_id]}" -> {edge_str}{edge_color};')
    content.append("}")
    out = pathlib.Path(output)
    out.write_text("\n".join(content), encoding="utf-8")


def process_graph(
    symbols: dict[pathlib.Path, list[str]],
    exports: dict[pathlib.Path, list[str]],
    output: pathlib.Path,
    colors: bool,
):
    "Creates a best effort dependency graph from symbols."
    idx = dict()
    symbol_to_module = dict()
    adjacency_list = list()
    modules = list()

    # Map symbol exported to module which exposes.
    for module, exported in exports.items():
        if not module in idx:
            idx[module] = len(idx)
            adjacency_list.append(set())
            modules.append(module.removesuffix(".ko"))
        exporter = idx.get(module)
        for symbol in exported:
            symbol_to_module[symbol] = exporter

    # Update the adjacency_list based on the links created by the undefined symbols.
    for module, undefined in symbols.items():
        to_id = idx.get(module)
        for symbol in undefined:
            if symbol not in symbol_to_module:
                continue
            from_id = symbol_to_module[symbol]
            adjacency_list[from_id].add(to_id)

    # Draw the dependencies.
    create_graphviz(modules, adjacency_list, output, colors)


def main():
    """Creates two maps of dependencies a directory full of kernel modules."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "adjacency_list_file",
        type=pathlib.Path,
        help="File with a graph represented as an adjacency list.",
    )
    parser.add_argument("output", help="Where to store the output")
    parser.add_argument(
        "--colors",
        action="store_true",
        help=(
            "Edges to dependents of a module share the same color. This is"
            " useful to differentiate dependencies of a module."
        ),
    )

    args = parser.parse_args()

    if not args.directory.is_dir():
        print(f"Expected a directory with binaries, but got {args.directory}")
        return 1

    # Locate the Kernel Binaries.
    vmlinux, modules = find_binaries(args.directory)

    # Extract undefined symbols and exported modules.
    symbols = extract_undefined_symbols_multiple(modules)
    exports = extract_exports_map([vmlinux] + modules)

    # Create a dependency graph & visualization.
    process_graph(symbols, exports, args.output, args.colors)


if __name__ == "__main__":
    sys.exit(main())
