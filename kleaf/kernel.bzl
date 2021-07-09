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

def _kernel_setup_config(config_target_name):
    return """
         # Restore inputs
           mkdir -p $${{OUT_DIR}}/include/
           cp $(location {config_target_name}/.config) $${{OUT_DIR}}/.config
           tar xf $(location {config_target_name}/include.tar.gz) -C $${{OUT_DIR}}
           """.format(config_target_name = config_target_name)

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
        build_config: the path to the build config from the directory containing
           the WORKSPACE file, e.g. "common/build.config.gki.aarch64"
        srcs: the kernel sources (a glob())
        outs: the expected output files. Two formats are supported:

          - If the list contains a single token {out}, the build rule
            automatically finds a file named {out} in the legacy kernel build
            output directory ${OUT_DIR}. Subdirectories are searched.
            (Implementation details: only files in ${FILES} are considered.)
            The file is copied to the output directory of {name},
            with the label {name}/{out}.

            {out} must not contain a slash.

            For example:
              kernel_build(name = "kernel_aarch64", outs = ["vmlinux"])
            The bulid system copies `${OUT_DIR}/<some subdirectory>/vmlinux`
            to `kernel_aarch64/vmlinux`.
            `kernel_aarch64/vmlinux` is the label to the file.

          - If the list contains two tokens separated by a colon "{path}:{out}",
            the build rule locates {path} under the legacy kernel
            build output directory ${OUT_DIR}. The file is copied to the
            output directory of {name} under {out}, with the label
            {name}/{out}.

            {out} may contain a slash.

            For example:
              kernel_build(
                name = "kernel_aarch64",
                outs = ["arch/arm64/boot/vmlinux:mydir/vmlinux"])
            The bulid system copies `${OUT_DIR}/arch/arm64/boot/vmlinux`
            to `kernel_aarch64/mydir/vmlinux`.
            `kernel_aarch64/mydir/vmlinux` is the label to the file.
        toolchain_version: the toolchain version to depend on
    """
    env_target_name = name + "_env"
    config_target_name = name + "_config"
    build_config_srcs = [
        s
        for s in srcs
        if "/build.config" in s or s.startswith("build.config")
    ]
    kernel_srcs = [s for s in srcs if s not in build_config_srcs]

    _env(env_target_name, build_config, build_config_srcs, **kwargs)
    _config(
        config_target_name,
        env_target_name,
        kernel_srcs,
        toolchain_version,
        **kwargs
    )
    _kernel_build(
        name,
        env_target_name,
        config_target_name,
        kernel_srcs,
        outs,
        toolchain_version,
        **kwargs
    )

def _env(name, build_config, build_config_srcs, **kwargs):
    """Generates a rule that generates a source-able build environment. A build
    environment is defined by a single build config file.

    Args:
        name: the name of the main build config
        build_config: the path to the build config from the directory containing
           the WORKSPACE file, e.g. "common/build.config.gki.aarch64"
        build_config_srcs: A list of labels. The source files that this build
          config may refer to, including itself.
          E.g. ["build.config.gki.aarch64", "build.config.gki"]
    """

    # No tools other than the following should be needed to run the cmd below.
    # source-ing these scripts should only set up an environment. No other tool
    # should be actually executed.
    kwargs["tools"] = [
        "//build:_setup_env.sh",
        "//build/kleaf:preserve_env.sh",
    ]
    native.genrule(
        name = name,
        srcs = build_config_srcs,
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

def _config(
        name,
        env_target_name,
        srcs,
        toolchain_version,
        **kwargs):
    """Defines a kernel config target.

    Args:
        name: the name of the kernel config
        env_target_name: A label that names the environment target of a
          kernel_build module, e.g. "kernel_aarch64_env"
        srcs: the kernel sources
        toolchain_version: the toolchain version to depend on
    """
    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(
        env_target_name,
        toolchain_version,
    )

    native.genrule(
        name = name,
        srcs = [s for s in srcs if s.startswith("scripts") or
                                   not s.endswith((".c", ".h"))],
        # e.g. kernel_aarch64/.config
        outs = [
            name + "/.config",
            name + "/include.tar.gz",
        ],
        cmd = _kernel_build_common_setup(env_target_name) + """
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

def _kernel_build(
        name,
        env_target_name,
        config_target_name,
        srcs,
        outs,
        toolchain_version,
        **kwargs):
    """Generates a kernel build rule."""

    kwargs["tools"] = kwargs.get("tools", [])
    kwargs["tools"] += _kernel_build_tools(env_target_name, toolchain_version)

    genrule_outs = []
    out_cmd = []
    for out in outs:
        if ":" in out:
            pair = out.split(":")
            if len(pair) != 2:
                fail('{name}: "{out}" is not a valid value of outs because it contains {length} colon-separated tokens, expected 2.'.format(name = name, out = out, length = len(pair)))
            src, dst = pair
            genrule_outs.append("{name}/{dst}".format(name = name, dst = dst))
            out_cmd.append("mv $${{OUT_DIR}}/{src} $(@D)/{name}/{dst}".format(name = name, src = src, dst = dst))
        else:
            if "/" in out:
                # This could be supported. However, to avoid confusion,
                # developers are required to use the full syntax to specify the
                # intent.
                fail('{name}: "{out}" is not a valid value of `outs` because it contains a slash. Perhaps you mean "{out}:{out}"?'.format(name = name, out = out))

            # Use indices to work around `Error: type 'string' is not iterable`
            # This is the sanitized version of {out} to be used as shell variables.
            sanitized = "".join([out[i] if out[i].isalnum() else "_" for i in range(len(out))])

            cmd = """
                  found_{sanitized}=
                  for file in $${{FILES}}; do
                    if [ "$$(basename $${{file}})" = "{out}" ]; then
                      if [ "$${{found_{sanitized}}}" != "" ]; then
                        echo "{name}: More than one file in FILES has the name {out}:"
                        echo "  $${{found_{sanitized}}}"
                        echo "  $${{file}}"
                        echo "In `outs` of \\"{name}\\", specify in the path:out syntax, e.g.:"
                        echo "  outs = ["
                        echo "    \\"$${{found_{sanitized}}}:$${{found_{sanitized}}}\\","
                        echo "    \\"$${{file}}:$${{file}}\\","
                        echo "  ],"
                        exit 1
                      fi
                      found_{sanitized}=$${{file}}
                      mv $${{OUT_DIR}}/$${{file}} $(@D)/{name}/{out}
                    fi
                  done
                  if [ "$${{found_{sanitized}}}" = "" ]; then
                    echo "{name}: \\"{out}\\" in `outs` does not match anything in FILES:"
                    echo "$${{FILES}}"
                    exit 1
                  fi
                  found_{sanitized}=
                  """.format(name = name, out = out, sanitized = sanitized)
            genrule_outs.append("{name}/{out}".format(name = name, out = out))
            out_cmd.append(cmd)

    native.genrule(
        name = name,
        srcs = srcs + [
            config_target_name + "/.config",
            config_target_name + "/include.tar.gz",
        ],
        # e.g. kernel_aarch64/vmlinux
        outs = genrule_outs,
        cmd = _kernel_build_common_setup(env_target_name) +
              _kernel_setup_config(config_target_name) +
              """
            # Actual kernel build
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{MAKE_GOALS}}
              """.format(name = name) +
              "\n".join(out_cmd),
        message = "Building kernel",
        **kwargs
    )
