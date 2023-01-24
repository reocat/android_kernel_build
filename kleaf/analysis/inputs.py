#!/usr/bin/env python3

"""Dumps the sha1sum of all dependent files of an aquery.

This helps you analyze why a specific action needs to be rebuilt when
building incrementally.

Example:

bazel build //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe
build/kernel/kleaf/analysis/inputs.py --config=fast \
    'mnemonic(KernelModule, //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe)'
# do some change to the code base that you don't expect it will affect this target
# then re-execute these two commands.
"""

import dataclasses
import errno
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


@dataclasses.dataclass(frozen=True, order=True)
class Path(object):
    path: pathlib.Path
    is_tree_artifact: bool


def analyze_inputs(args):
    text_result = subprocess.check_output(
        [
            "tools/bazel",
            "aquery",
            "--output=jsonproto"
        ] + args,
        text=True,
    )
    json_result = json.loads(text_result)

    # https://github.com/bazelbuild/bazel/blob/master/src/main/protobuf/analysis_v2.proto

    actions = json_result["actions"]
    artifacts = id_object_list_to_dict(json_result["artifacts"])
    dep_set_of_files = id_object_list_to_dict(json_result["depSetOfFiles"])
    path_fragments = id_object_list_to_dict(json_result["pathFragments"])

    inputs: set[Path] = set()
    for action in actions:
        inputs |= load_inputs(action,
                              dep_set_of_files=dep_set_of_files,
                              artifacts=artifacts,
                              path_fragments=path_fragments)

    inputs = resolve_inputs(inputs)

    hash_results = hash_all(inputs)

    print(json.dumps(hash_results, indent=2, sort_keys=True))


def id_object_list_to_dict(l: list[dict[str, Any]]) -> dict[int, dict[str, Any]]:
    ret = {}
    for elem in l:
        ret[elem["id"]] = elem
    return ret


def load_inputs(action: dict[str, Any],
                dep_set_of_files: dict[int, dict[str, Any]],
                artifacts: dict[int, dict[str, Any]],
                path_fragments: dict[int, dict[str, Any]],
                ) -> set[Path]:
    all_inputs_artifact_ids = dep_set_to_artifact_ids(
        dep_set_ids=action["inputDepSetIds"],
        dep_set_of_files=dep_set_of_files,
    )

    return artifacts_to_paths(
        artifact_ids=all_inputs_artifact_ids,
        artifacts=artifacts,
        path_fragments=path_fragments,
    )


# TODO ignore visited
def dep_set_to_artifact_ids(
        dep_set_ids: list[int],
        dep_set_of_files: dict[int, dict[str, Any]]
) -> set[int]:
    ret = set()
    for dep_set_id in dep_set_ids:
        dep_set = dep_set_of_files[dep_set_id]
        ret |= set(dep_set["directArtifactIds"])
        if dep_set.get("transitiveDepSetIds"):
            ret |= dep_set_to_artifact_ids(
                dep_set_ids=dep_set["transitiveDepSetIds"],
                dep_set_of_files=dep_set_of_files)
    return ret


# TODO cache
def artifacts_to_paths(artifact_ids: set[int],
                       artifacts: dict[int, dict[str, Any]],
                       path_fragments: dict[int, dict[str, Any]]) -> set[Path]:
    ret = set()
    for artifact_id in artifact_ids:
        artifact = artifacts[artifact_id]
        path = Path(
            path=pathlib.Path(*get_path(
                path_fragment_id=artifact["pathFragmentId"],
                path_fragments=path_fragments,
            )),
            is_tree_artifact=bool(artifact.get("isTreeArtifact")))
        ret.add(path)
    return ret


def get_path(
        path_fragment_id: int,
        path_fragments: dict[int, dict[str, Any]]
) -> list[str]:
    path_fragment = path_fragments[path_fragment_id]
    if path_fragment.get("parentId"):
        ret = get_path(
            path_fragment_id=path_fragment["parentId"],
            path_fragments=path_fragments)
    else:
        ret = []
    ret.append(path_fragment["label"])
    return ret


def hash_all(paths: set[Path]) -> dict[str, str]:
    files: set[pathlib.Path] = set()
    for path in paths:
        if path.is_tree_artifact:
            files |= walk_files(path.path)
        else:
            files.add(path.path)

    exists, missing = split_existing_files(files)

    return hash_all_files(list(exists)) | {
        file: None for file in missing
    }


def hash_all_files(files: list[pathlib.Path]) -> dict[str, str]:
    try:
        output = subprocess.check_output([
                                             "sha1sum"
                                         ] + list(str(path) for path in files),
                                         text=True).splitlines()
        ret = dict()
        for line in output:
            sha1sum, path = line.split(maxsplit=2)
            ret[path] = sha1sum

        return ret
    except OSError as e:
        if e.errno != errno.E2BIG:
            raise e

        mid = len(files) // 2
        head = files[:mid]
        tail = files[mid:]

        if not head or not tail:
            raise e

        return hash_all_files(head) | hash_all_files(tail)


def walk_files(path: pathlib.Path):
    ret = set()
    for root, dir, files in os.walk(path):
        ret |= set(pathlib.Path(root) / file for file in files)
    return ret


def resolve_inputs(inputs: set[Path]) -> set[Path]:
    resolved_inputs: set[Path] = set()
    execroot = get_execroot()
    for input in inputs:
        if input.path.is_relative_to("external"):
            if (execroot / input.path).exists() and \
                    (execroot / input.path).is_dir() == input.is_tree_artifact:
                resolved_inputs.add(Path(
                    path=execroot / input.path,
                    is_tree_artifact=input.is_tree_artifact,
                ))
            elif input.path.exists() and \
                    input.path.is_dir() == input.is_tree_artifact:
                resolved_inputs.add(input)
            else:
                raise FileNotFoundError(input.path)
        else:
            resolved_inputs.add(input)

    return resolved_inputs


def get_execroot():
    return pathlib.Path("bazel-out").resolve().parent.relative_to(pathlib.Path(".").resolve())


def split_existing_files(files: set[pathlib.Path]):
    exists = set()
    missing = set()

    for file in files:
        if file.exists():
            exists.add(file)
        else:
            missing.add(file)
    return exists, missing

if __name__ == "__main__":
    analyze_inputs(sys.argv[1:])
