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

"""Provides utility functions for tests."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:utils.bzl", "kernel_utils")

def _find_action(ctx, env_or_actions, mnemonic, add_local_suffix = None):
    """Finds an action with the given mnemonic.

    Args:
        ctx: ctx
        env_or_actions: env, or a list of actions
        mnemonic: expected mnemonic.
        add_local_suffix: If True, adds "Local" to the expected mnemonic when --config=local
    """

    if add_local_suffix:
        mnemonic += kernel_utils.local_mnemonic_suffix(ctx)

    if type(env_or_actions) == type([]):
        actions = env_or_actions
    else:
        actions = analysistest.target_actions(env_or_actions)

    for action in actions:
        if action.mnemonic == mnemonic:
            return action

    asserts.true(env, False, "No matching action with mnemonic {} found".format(mnemonic))
    return None

def _get_shell_script(env, action):
    """Assuming the action is a `run_shell`, returns the script.

    Args:
        env: env
        action: the action.
    """
    argv = action.argv
    asserts.equals(env, 3, len(argv), "run_shell action should contain 3 args")
    return argv[2]

test_utils = struct(
    find_action = _find_action,
    get_shell_script = _get_shell_script,
)
