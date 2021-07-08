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
        build_config,
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

        Two additional labels, "{name}_env" and "{name}_config", are generated.
        For example, if name is "kernel_aarch64":
        - kernel_aarch64_env provides a source-able build environment defined
          by the build config.
        - kernel_aarch64_config provides the kernel config.

    Args:
        name: the final kernel target name, e.g. "kernel_aarch64"
        build_config: the path to the build config from the top of the kernel
          tree, e.g. "common/build.config.gki.aarch64"
        srcs: the kernel sources (a glob())
        outs: the expected output files. For each output file specified here, a
          label "{name}/{output_file}" is created to refer to the output file.
          For example, if
            name = "kernel_aarch64",
            outs = ["foo/bar"],
          then label "kernel_aarch64/foo/bar" is created to refer to the output
          file.
        toolchain_version: the toolchain version to depend on
    """
    sources_target = name + "_sources"
    env_target = name + "_env"
    config_target = name + "_config"
    build_config_srcs = [
        s
        for s in srcs
        if "/build.config" in s or s.startswith("build.config")
    ]
    kernel_srcs = [s for s in srcs if s not in build_config_srcs]

    _env(env_target, build_config, build_config_srcs, **kwargs)
    native.filegroup(name = sources_target, srcs = kernel_srcs)
    _config(config_target, env_target, [sources_target], toolchain_version, **kwargs)
    _kernel_build(
        name,
        env_target,
        config_target,
        [sources_target],
        outs,
        toolchain_version,
        **kwargs
    )

def _env(name, build_config, srcs, **kwargs):
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

def _config(name, env, srcs, toolchain_version, **kwargs):
    """Defines a kernel config target.

    Args:
        name: the name of the kernel config
        env: A label that names the environment target of a kernel_build module,
          e.g. "kernel_aarch64_env"
        srcs: the kernel sources
        toolchain_version: the toolchain version to depend on
    """
    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(env, toolchain_version)
    common_setup = _kernel_build_common_setup(env)

    native.genrule(
        name = name,
        srcs = [s for s in srcs if s.startswith("scripts") or not s.endswith((".c", ".h"))],
        outs = [
            name + "/.config",
            name + "/include.tar.gz",
        ],
        cmd = common_setup + """
            # Pre-defconfig commands
              eval $${{PRE_DEFCONFIG_CMDS}}
            # Actual defconfig
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{DEFCONFIG}}
            # Post-defconfig commands
              eval $${{POST_DEFCONFIG_CMDS}}
            # Grab outputs
              mv $${{OUT_DIR}}/.config $(location {name}/.config)
              tar czf $(location {name}/include.tar.gz) -C $${{OUT_DIR}} include/
            """.format(name = name),
        message = "Configuring kernel",
        **kwargs
    )

def _kernel_build(name, env, config, srcs, outs, toolchain_version, **kwargs):
    """Generates a kernel build rule."""
    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(env, toolchain_version)
    common_setup = _kernel_build_common_setup(env)

    native.genrule(
        name = name,
        srcs = srcs + [
            config + "/.config",
            config + "/include.tar.gz",
        ],
        outs = [name + "/" + file for file in outs],  # e.g. kernel_aarch64/vmlinux
        cmd = common_setup + """
            # Restore inputs
              mkdir -p $${{OUT_DIR}}/include/
              cp $(location {config}/.config) $${{OUT_DIR}}/.config
              tar xf $(location {config}/include.tar.gz) -C $${{OUT_DIR}}
            # Actual kernel build
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{MAKE_GOALS}}
            # Move outputs into place
              for i in $${{FILES}}; do mv $${{OUT_DIR}}/$$i $(@D)/{name}/$$i; done
            """.format(name = name, config = config),
        message = "Building kernel",
        **kwargs
    )

def kernel_module(
        name,
        kernel_build,
        srcs,
        outs,
        makefile = "Makefile",
        toolchain_version = "r416183b",
        **kwargs):
    """Defines a kernel module target.

    Args:
        name: the kernel module name
        kernel_build: a label referring to a kernel_build target
        srcs: the sources for building the kernel module
        outs: the expected output files. For each output file specified here, a
          label "{name}/{output_file}" is created to refer to the output file.
          For example, if
            name = "kernel_aarch64",
            outs = ["foo/bar"],
          then label "kernel_aarch64/foo/bar" is created to refer to the output
          file.
        makefile: location of the Makefile. This is where "make" is
          executed on ("make -C $(dirname ${makefile})").
        toolchain_version: the toolchain version to depend on
    """
    env = kernel_build + "_env"
    config = kernel_build + "_config"
    kernel_sources = kernel_build + "_sources"

    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(env, toolchain_version)
    common_setup = _kernel_build_common_setup(env)

    additional_srcs = [
        kernel_build,
        kernel_build + "/vmlinux",
        kernel_sources,
        config + "/.config",
        config + "/include.tar.gz",
    ]
    if makefile not in srcs:
        additional_srcs.append(makefile)

    native.genrule(
        name = name,
        srcs = srcs + additional_srcs,
        outs = [name + "/" + file for file in outs],
        cmd = common_setup + """
            # Set MODULE_STRIP_FLAG
              if [ "$${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
                MODULE_STRIP_FLAG="INSTALL_MOD_STRIP=1"
              fi
            # Set MODULES_STAGING_DIR
              MODULES_STAGING_DIR=$$(readlink -m $${{COMMON_OUT_DIR}}/staging)
            # Restore inputs from _config
              mkdir -p $${{OUT_DIR}}/include/
              cp $(location {config}/.config) $${{OUT_DIR}}/.config
              tar xf $(location {config}/include.tar.gz) -C $${{OUT_DIR}}
            # Restore inputs from kernel_build.
            # Use vmlinux as an anchor to find the directory, then copy all
            # contents of the directory to OUT_DIR
              cp -R $$(dirname $(location {kernel_build}/vmlinux))* $${{OUT_DIR}}
            # Actual kernel module build
              make -C $$(dirname $(location {makefile})) $${{TOOL_ARGS}} O=$${{OUT_DIR}} KERNEL_SRC=$${{ROOT_DIR}}/$${{KERNEL_DIR}}
            # Install into staging directory
              make -C $$(dirname $(location {makefile})) $${{TOOL_ARGS}} O=$${{OUT_DIR}} KERNEL_SRC=$${{ROOT_DIR}}/$${{KERNEL_DIR}} INSTALL_MOD_PATH=$${{MODULES_STAGING_DIR}} $${{MODULE_STRIP_FLAG}} modules_install
            # Move outputs into place
              for i in {outs}; do mv $${{MODULES_STAGING_DIR}}/lib/modules/*/extra/$$i $(@D)/{name}/$$i; done
            """.format(name = name, config = config, makefile = makefile, kernel_build = kernel_build, outs = " ".join(outs)),
        message = "Building external module",
        **kwargs
    )
