# Copyright (C) 2021 The Android Open Source Project
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

def _kernel_build_tools(env, toolchain_version):
    return [
        env,
        "//build:kernel-abi-scripts",
        "//build:kernel-build-scripts",
        "//build:host-tools",
        "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
        "//prebuilts/build-tools:linux-x86",
        "//prebuilts/kernel-build-tools:linux-x86",
    ]

def _kernel_build_common_setup(env):
    return """
            # do not fail upon unset variables being read
              set +u
            # source the build environment
              source $(location {env})
            # setup the PATH to also include the host tools
              export PATH=$$PATH:$$PWD/$$(dirname $$( echo $(locations //build:host-tools) | tr ' ' '\n' | head -n 1 ) )
            """.format(env = env)

def kernel_build(
        name,
        env,
        config,
        srcs,
        outs,
        toolchain_version = "r416183b",
        **kwargs):
    """Defines a kernel build target with all dependent targets.

        It uses a build_config to construct a deterministic build environment
        (e.g. 'common/build.config.gki.aarch64'). The kernel sources need to be
        declared via srcs (using a glob). outs declares the output files
        that are surviving the build. The effective output file names will be
        $(name)/$(output_file). Any other artifact is not guaranteed to be
        accessible after the rule has run. The default toolchain_version is
        defined with a sensible default, but can be overriden.

    Args:
        name: the final kernel target name
        env: A label that names a "kernel_env" module
        config: A label that names a "kernel_config" module
        srcs: the kernel sources (a glob())
        outs: the expected output files
        toolchain_version: the toolchain version to depend on
    """
    _kernel_build(name, env, config, srcs, outs, toolchain_version, **kwargs)

def kernel_config(
        name,
        env,
        srcs,
        toolchain_version = "r416183b",
        **kwargs):
    """Defines a kernel config target.

    Args:
        name: the name of the kernel config
        env: A label that names a "kernel_env" module
        srcs: the kernel sources
        toolchain_version: the toolchain version to depend on
    """
    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(env, toolchain_version)
    common_setup = _kernel_build_common_setup(env)

    native.genrule(
        name = name,
        srcs = [s for s in srcs if s.startswith("scripts") or not s.endswith((".c", ".h"))],
        outs = [
            name + ".tar.gz",
        ],
        cmd = common_setup + """
            # Pre-defconfig commands
              eval $${{PRE_DEFCONFIG_CMDS}}
            # Actual defconfig
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{DEFCONFIG}}
            # Post-defconfig commands
              eval $${{POST_DEFCONFIG_CMDS}}
            # Grab outputs
              tar czf $(location {name}.tar.gz) -C $${{OUT_DIR}} .config include/
            """.format(name = name),
        message = "Configuring kernel",
        **kwargs
    )

def kernel_env(
        name,
        build_config,
        srcs,
        **kwargs):
    """Generates a rule that generates a source-able build environment. A build
    environment is defined by a single build config file.

    Args:
        name: the name of the build config
        build_config: the path to the build config from the top of the kernel
          tree, e.g. "common/build.config.gki.aarch64"
        srcs: A list of labels. The source files that this build config may
          refer to, including itself.
          E.g. ["build.config.gki.aarch64", "build.config.gki"]
    """
    kwargs["tools"] = [
        "//build:_setup_env.sh",
        "//build/kleaf:preserve_env.sh",
    ]
    native.genrule(
        name = name,
        srcs = srcs,
        outs = [name + ".sh"],
        cmd = """
            # do not fail upon unset variables being read
              set +u
            # Run Make in silence mode to suppress most of the info output
              export MAKEFLAGS="$${MAKEFLAGS} -s"
            # Increase parallelism # TODO(b/192655643): do not use -j anymore
              export MAKEFLAGS="$${MAKEFLAGS} -j$$(nproc)"
            # create a build environment
              export BUILD_CONFIG=%s
              source $(location //build:_setup_env.sh)
            # capture it as a file to be sourced in downstream rules
              $(location //build/kleaf:preserve_env.sh) > $@
            """ % build_config,
        **kwargs
    )

def _kernel_build(name, env, config, srcs, outs, toolchain_version, **kwargs):
    """Generates a kernel build rule."""
    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(env, toolchain_version)
    common_setup = _kernel_build_common_setup(env)

    native.genrule(
        name = name,
        srcs = srcs + [
            config,
        ],
        outs = [name + "/" + file for file in outs],  # e.g. kernel_aarch64/vmlinux
        cmd = common_setup + """
            # Restore inputs
              mkdir -p $${{OUT_DIR}}/include/
              tar xf $(location {config}) -C $${{OUT_DIR}}
            # Actual kernel build
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{MAKE_GOALS}}
            # Move outputs into place
              for i in $${{FILES}}; do mv $${{OUT_DIR}}/$$i $$(dirname $(location {name}/vmlinux)); done
            """.format(name = name, config = config),
        message = "Building kernel",
        **kwargs
    )
