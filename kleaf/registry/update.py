#!/usr/bin/env python3

# Update the registry.
# Execute with:
#    build/kernel/kleaf/registry/update.py

import collections
import dataclasses
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

_COMMON_BAZEL_ARGS = [
    "--enable_bzlmod",
    "--config=internet",
    f"--registry={_REGISTRY}",
]


@dataclasses.dataclass(frozen=True)
class ModuleVersion:
    module_name: str
    version: str
    unused: bool

    def canonical_repo_name(self):
        # https://github.com/bazelbuild/bazel/issues/20397
        if self.module_name == "platforms":
            return self.module_name
        return f"{self.module_name}~{self.version}"


def main():
    if not pathlib.Path(_BAZEL).exists():
        logging.error("%s is not found. Run this script at workspace root!",
                      pathlib.Path(_BAZEL).absolute())
        sys.exit(1)

    mod_graph = _load_mod_graph()
    module_versions_dict = _get_module_versions(mod_graph)
    _download_module_registries(module_versions_dict)
    _fetch_modules(module_versions_dict)


def _load_mod_graph() -> dict[str, Any]:
    logging.info("Loading mod graph")
    return json.loads(subprocess.check_output([
        _BAZEL,
        "mod",
        "graph",
        "--include_builtin",
        "--include_unused",
        "--output=json",
        "--verbose",
    ] + _COMMON_BAZEL_ARGS, text=True))


def _get_module_versions(mod_graph: dict[str, Any]) -> set[ModuleVersion]:
    module_versions = set[str]()
    _walk_mod_graph(mod_graph, module_versions)
    logging.info(module_versions)
    return module_versions


def _walk_mod_graph(mod_graph: dict[str, Any], module_versions: set[ModuleVersion]):
    key = mod_graph["key"]

    if key != "<root>" and "@" not in key:
        logging.error("Unrecognized repo name %s", key)
        sys.exit(1)

    if "@" in key:
        module_name, version = key.split("@", 1)
        # <name>@_ is for builtin modules
        if version != "_":
            unused = mod_graph.get("unused", False)
            module_versions.add(ModuleVersion(module_name, version, unused))

    # bazel mod already trims visited edges, so no need to optimize for
    # visited edges here.
    for dep in mod_graph.get("dependencies", []):
        _walk_mod_graph(dep, module_versions)


def _download_module_registries(module_versions: set[ModuleVersion]):
    # return  # FIXME this is skipped for now
    modules_dir = _LOCAL_REGISTRY / "modules"
    if modules_dir.is_dir():
        shutil.rmtree(modules_dir)
    modules_dir.mkdir()

    module_versions_dict: dict[str, set[ModuleVersion]] = collections.defaultdict(set)
    for module_version in module_versions:
        module_versions_dict[module_version.module_name].add(module_version)
    for module_name, module_versions in module_versions_dict.items():
        _download_module_registry(module_name, module_versions)


def _download_module_registry(module_name: str, module_versions: set[ModuleVersion]):
    """Pull necessary versions of a module from BCR to local registry"""
    logging.info("Downloading module %s", module_name)
    module_dir = pathlib.Path("modules", module_name)
    _download(module_dir / "metadata.json",
              lambda remote_file, local_file: _inject_versions(remote_file, local_file, module_versions))

    for module_version in module_versions:
        logging.info("Downloading registry for %s@%s",
                     module_name, module_version.version)
        version_dir = module_dir / module_version.version
        _download(version_dir / "MODULE.bazel")
        _download(version_dir / "source.json")

        with open(_LOCAL_REGISTRY / version_dir / "source.json") as f:
            source_json = json.load(f)
            for patch_name in source_json.get("patches", {}):
                _download(version_dir / "patches" / patch_name)


def _inject_versions(remote_file: BytesIO, local_file: BytesIO, module_versions: set[ModuleVersion]):
    metadata = json.load(io.TextIOWrapper(remote_file, "utf-8"))
    metadata["versions"] = [
        module_version.version for module_version in module_versions]
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


def _fetch_modules(module_versions_dict: dict[str, set[ModuleVersion]]):
    used = set[ModuleVersion]()
    for module_versions in module_versions_dict.values():
        used.update(module_version for module_version in module_versions if module_version.used)

    subprocess.check_call([
        _BAZEL,
        "fetch",
    ] + _COMMON_BAZEL_ARGS + [
        f"--repo=@@{module_version.canonical_repo_name()}" for module_version in used
    ])

    output_base = pathlib.Path(subprocess.check_output(
        [_BAZEL, "info", "output_base"], text=True).strip())

    cache_dir = _LOCAL_REGISTRY / "cache"
    if cache_dir.is_dir():
        shutil.rmtree(cache_dir)

    for module_version in used:
        shutil.copytree(output_base / "external" / module_version.canonical_repo_name(),
                        cache_dir / module_version.canonical_repo_name())


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")
    main()
