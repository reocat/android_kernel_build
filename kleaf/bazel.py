# Copyright (C) 2022 The Android Open Source Project
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

import argparse
import os
import pathlib
import shutil
import sys
import traceback
from typing import Tuple, Optional


def _require_absolute_path(p: str) -> pathlib.Path:
    p = pathlib.Path(p)
    if not p.is_absolute():
        raise argparse.ArgumentTypeError("need to specify an absolute path")
    return p


def _split_triple(lst: list[str], index: int) -> Tuple[list[str], Optional[str], list[str]]:
    """Return the triple split by index. That is, return a tuple:
        (everything before index, the element at index, everything after index)

    If index is None, return (the list, None, empty list)
    """
    if index is None:
        return lst[:], None, []
    return lst[:index], lst[index], lst[index + 1:]


def _split_bazel_args(bazel_args: list[str]) \
        -> Tuple[list[str], Optional[str], list[str], Optional[str], list[str]]:
    """Split arguments to the bazel binary based on the functionality.

    bazel [startup_options] command         [command_args] --               [target_patterns]
                             ^- command_idx                ^- dash_dash_idx

    See https://bazel.build/reference/command-line-reference

    Args:
        bazel_args: The list of arguments the user provides through command line
    Return:
        A tuple of (startup_options, command, command_args, dash_dash, target_patterns)
    """

    command_idx = None
    for idx, arg in enumerate(bazel_args):
        if not arg.startswith("-"):
            command_idx = idx
            break

    startup_options, command, remaining_args = _split_triple(bazel_args, command_idx)

    # Split command_args into `command_args -- target_patterns`
    dash_dash_idx = None
    try:
        dash_dash_idx = remaining_args.index("--")
    except ValueError:
        # If -- is not found, put everything in command_args. These arguments
        # are not provided to the Bazel executable target.
        pass

    command_args, dash_dash, target_patterns = _split_triple(remaining_args, dash_dash_idx)

    return startup_options, command, command_args, dash_dash, target_patterns


def _parse_command_args(command_args: list[str], absolute_out_dir: str) -> \
        Tuple[argparse.Namespace, list[str], dict[str, str]]:
    """Parse the given list of command_args.

    Args:
        command: see _split_bazel_args
        command_args: see _split_bazel_args
        absolute_out_dir: Absolute path to the out directory.
    Return:
        A tuple (known_args, transformed_command_args, updated_environment_variables)
        where:
        - known_args: A namespace holding options known by this Bazel wrapper script
        - transformed_command_args: The transformed list of command_args to replace
          existing command_args to be fed to the Bazel binary
        - updated_environment_variables: A dictionary containing environment variables
          to be updated.
    """

    absolute_cache_dir = f"{absolute_out_dir}/cache"
    env = {}

    # Arguments known by this bazel wrapper.
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--use_prebuilt_gki")
    parser.add_argument("--experimental_strip_sandbox_path",
                        action='store_true')
    parser.add_argument("--make_jobs", type=int, default=None)
    parser.add_argument("--cache_dir",
                        type=_require_absolute_path,
                        default=absolute_cache_dir)

    # known_args: List of arguments known by this bazel wrapper. These
    #   are stripped from the final bazel invocation.
    # remaining_command_args: the rest of the arguments
    # Skip startup options (before command) and target_patterns (after --)
    known_args, remaining_command_args = parser.parse_known_args(command_args)

    if known_args.use_prebuilt_gki:
        remaining_command_args.append("--//common:use_prebuilt_gki")
        env["KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"] = f"gki_prebuilts={known_args.use_prebuilt_gki}"

    if known_args.make_jobs is not None:
        env["KLEAF_MAKE_JOBS"] = str(known_args.make_jobs)

    remaining_command_args.append(f"--//build/kernel/kleaf:cache_dir={known_args.cache_dir}")

    return known_args, remaining_command_args, env


def main(root_dir, bazel_args, env):
    bazel_path = f"{root_dir}/prebuilts/bazel/linux-x86_64/bazel"
    bazel_jdk_path = f"{root_dir}/prebuilts/jdk/jdk11/linux-x86"
    bazelrc_name = "build/kernel/kleaf/common.bazelrc"

    absolute_out_dir = f"{root_dir}/out"

    startup_options, command, command_args, dash_dash, target_patterns = \
        _split_bazel_args(bazel_args)

    known_args, transformed_command_args, env_update = \
        _parse_command_args(command_args, absolute_out_dir)
    updated_env = env.copy()
    updated_env.update(env_update)

    additional_startup_options = [
        f"--server_javabase={bazel_jdk_path}",
        f"--output_user_root={absolute_out_dir}/bazel/output_user_root",
        f"--host_jvm_args=-Djava.io.tmpdir={absolute_out_dir}/bazel/javatmp",
        f"--bazelrc={root_dir}/{bazelrc_name}",
    ]

    # final_args:
    # bazel [startup_options] [additional_startup_options] command [transformed_command_args] -- [target_patterns]

    final_args = [bazel_path] + startup_options + additional_startup_options
    if command is not None:
        final_args.append(command)
    final_args += transformed_command_args
    if dash_dash is not None:
        final_args.append(dash_dash)
    final_args += target_patterns

    if command == "clean":
        shutil.rmtree(known_args.cache_dir, ignore_errors=True)
    else:
        os.makedirs(known_args.cache_dir, exist_ok=True)

    if known_args.experimental_strip_sandbox_path:
        import asyncio
        import re
        filter_regex = re.compile(absolute_out_dir + "/\S+?/sandbox/.*?/__main__/")
        asyncio.run(run(final_args, env, filter_regex))
    else:
        os.execve(path=bazel_path, argv=final_args, env=updated_env)


async def output_filter(input_stream, output_stream, filter_regex):
    import re
    while not input_stream.at_eof():
        output = await input_stream.readline()
        output = re.sub(filter_regex, "", output.decode())
        output_stream.buffer.write(output.encode())
        output_stream.flush()


async def run(command, env, filter_regex):
    import asyncio
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
    )

    await asyncio.gather(
        output_filter(process.stderr, sys.stderr, filter_regex),
        output_filter(process.stdout, sys.stdout, filter_regex),
    )
    await process.wait()


if __name__ == "__main__":
    main(root_dir=sys.argv[1], bazel_args=sys.argv[2:], env=os.environ)
