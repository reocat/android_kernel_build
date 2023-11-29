#!/usr/bin/env python3

# Update the registry.
# Execute with:
#    build/kernel/kleaf/registry/update.py

import collections
from io import BytesIO
import io
import json
import logging
import shutil
import subprocess
import os
import pathlib
import sys
from typing import Any, Callable

import urllib.request


_BAZEL = "tools/bazel"
_REGISTRY = "https://bcr.bazel.build"
_LOCAL_REGISTRY = pathlib.Path(__file__).relative_to(
    pathlib.Path(os.getcwd())).parent


def main():
    if not pathlib.Path(_BAZEL).exists():
        logging.error("%s is not found. Run this script at workspace root!",
                      pathlib.Path(_BAZEL).absolute())
        sys.exit(1)


    mod_graph = _load_mod_graph()

    module_versions_dict = _get_module_versions(mod_graph)

    modules_dir = _LOCAL_REGISTRY / "modules"
    if modules_dir.is_dir():
        shutil.rmtree(modules_dir)
    modules_dir.mkdir()

    for module_name, module_versions in module_versions_dict.items():
        _download_module(module_name, module_versions)


def _load_mod_graph() -> dict[str, Any]:
    logging.info("Loading mod graph")
    return json.loads(subprocess.check_output([
        _BAZEL,
        "mod",
        "graph",
        "--enable_bzlmod",
        "--config=internet",
        "--include_builtin",
        "--output=json",
        "--verbose",
        "--include_unused",
        f"--registry={_REGISTRY}",
    ]))


def _get_module_versions(mod_graph: dict[str, Any]) -> dict[str, set[str]]:
    module_versions_dict: dict[str, set[str]] = collections.defaultdict(set)
    _walk_mod_graph(mod_graph, module_versions_dict)
    print(module_versions_dict)
    return module_versions_dict

def _walk_mod_graph(mod_graph: dict[str, Any], module_versions_dict: dict[str, set[str]]):
    key = mod_graph["key"]

    if "@" in key:
        module_name, version = key.split("@", 1)
        original_version = mod_graph.get("originalVersion", version)
        if not original_version:
            original_version = version
        # <name>@_ is for builtin modules
        if original_version != "_":
            module_versions_dict[module_name].add(original_version)
    elif key != "<root>":
        logging.error("Unrecognized repo name %s", key)
        sys.exit(1)

    # bazel mod already trims visited edges, so no need to optimize for
    # visited edges here.
    for dep in mod_graph.get("dependencies", []):
        _walk_mod_graph(dep, module_versions_dict)


def _download_module(module_name: str, module_versions: set[str]):
    """Pull necessary versions of a module from BCR to local registry"""
    logging.info("Downloading module %s", module_name)
    module_dir = pathlib.Path("modules", module_name)
    _download(module_dir / "metadata.json",
              lambda remote_file, local_file: _inject_versions(remote_file, local_file, module_versions))

    for module_version in module_versions:
        logging.info("Downloading %s@%s", module_name, module_version)
        version_dir = module_dir / module_version
        _download(version_dir / "MODULE.bazel")
        _download(version_dir / "source.json")

        with open(_LOCAL_REGISTRY / version_dir / "source.json") as f:
            source_json = json.load(f)
            for patch_name in source_json.get("patches", {}):
                _download(version_dir / "patches" / patch_name)

def _inject_versions(remote_file: BytesIO, local_file: BytesIO, module_versions: set[str]):
    metadata = json.load(io.TextIOWrapper(remote_file, "utf-8"))
    metadata["versions"] = list(module_versions)
    json.dump(metadata, io.TextIOWrapper(local_file, "utf-8"),
              sort_keys=True, indent=4)


def _download(
        path: pathlib.Path,
        copyfile: Callable[[BytesIO, BytesIO], None] = shutil.copyfileobj):
    """Download a file from BCR to local registry."""
    url = f"{_REGISTRY}/{path}"
    local = _LOCAL_REGISTRY / path
    local.parent.mkdir(parents=True, exist_ok=True)

    try:
        with urllib.request.urlopen(url) as remote_file, \
                open(local, 'wb') as local_file:
            copyfile(remote_file, local_file)
    except urllib.error.HTTPError:
        logging.error("Cannot download %s", url)
        raise


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")
    main()
