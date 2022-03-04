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

load(":utils.bzl", "get_stable_status_cmd")

def _host_tools_impl(ctx):
    inputs = [ctx.info_file]

    command = """
        export PATH={path_cmd}
        for i in {outs}; do
          ln -s $(which $(basename $i)) $i;
        done
""".format(
        path_cmd = get_stable_status_cmd(ctx, "STABLE_PATH"),
        outs = " ".join([out.path for out in ctx.outputs.outs]),
    )
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = ctx.outputs.outs,
        command = command,
        progress_message = "Creating symlinks to host tools",
        mnemonic = "HostTools",
        execution_requirements = {"no-remote": "1"},
    )

host_tools = rule(
    implementation = _host_tools_impl,
    doc = "Provide access to some host tools for rules wanting to restrict `PATH`.",
    attrs = {
        "outs": attr.output_list(
            doc = "An allowlist of binaries to be found from host.",
        ),
    },
)
