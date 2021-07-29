<!-- Generated with Stardoc: http://skydoc.bazel.build -->

<a name="#kernel_module"></a>

## kernel_module

<pre>
kernel_module(<a href="#kernel_module-name">name</a>, <a href="#kernel_module-kernel_build">kernel_build</a>, <a href="#kernel_module-kernel_module_deps">kernel_module_deps</a>, <a href="#kernel_module-makefile">makefile</a>, <a href="#kernel_module-outs">outs</a>, <a href="#kernel_module-srcs">srcs</a>)
</pre>

Generates a rule that builds an external kernel module.

Example:
```
kernel_module(
    name = "nfc",
    srcs = glob([
        "**/*.c",
        "**/*.h",

        # If there are Kbuild files, add them
        "**/Kbuild",
        # If there are additional makefiles in subdirectories, add them
        "**/Makefile",
    ]),
    outs = ["nfc.ko"],
    kernel_build = "//common:kernel_aarch64",
    makefile = ":Makefile",
)
```


### Attributes


#### name {:#kernel_module-name}

*<a href="https://bazel.build/docs/build-ref.html#name">Name</a>.*  *Required.*   A unique name for this target.

#### kernel_build {:#kernel_module-kernel_build}

*<a href="https://bazel.build/docs/build-ref.html#labels">Label</a>.*  *Required.*   Label referring to the kernel_build module.

#### kernel_module_deps {:#kernel_module-kernel_module_deps}

*<a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a>.*  *Optional.*   *Default is* `[]`.  A list of other kernel_module dependencies.

#### makefile {:#kernel_module-makefile}

*<a href="https://bazel.build/docs/build-ref.html#labels">Label</a>.*  *Optional.*   *Default is* `None`.  Label referring to the makefile. This is where `make` is executed on (`make -C $(dirname ${makefile})`).

#### outs {:#kernel_module-outs}

*List of labels.*  *Optional.*   *Default is* `None`.  The expected output files.

For each token `out`, the build rule automatically finds a
file named `out` in the legacy kernel modules staging
directory. The file is copied to the output directory of
this package, with the label `out`.

- If `out` doesn't contain a slash, subdirectories are searched.

    Example:
    ```
    kernel_module(name = "nfc", outs = ["nfc.ko"])
    ```

    The build system copies
    ```
    <legacy modules staging dir>/lib/modules/*/extra/<some subdir>/nfc.ko
    ```
    to
    ```
    <package output dir>/nfc.ko
    ```

    `nfc.ko` is the label to the file.

- If {out} contains slashes, its value is used. The file is
  also copied to the top of package output directory.

    For example:
    ```
    kernel_module(name = "nfc", outs = ["foo/nfc.ko"])
    ```

    The build system copies
    ```
    <legacy modules staging dir>/lib/modules/*/extra/foo/nfc.ko
    ```
    to
    ```
    foo/nfc.ko
    ```

    `foo/nfc.ko` is the label to the file.

    The file is also copied to `<package output dir>/nfc.ko`.

    `nfc.ko` is the label to the file.

    See `search_and_mv_output.py` for details.


#### srcs {:#kernel_module-srcs}

*<a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a>.*  *Required.*   Source files to build this kernel module.



<a name="#kernel_build"></a>

## kernel_build

<pre>
kernel_build(<a href="#kernel_build-name">name</a>, <a href="#kernel_build-build_config">build_config</a>, <a href="#kernel_build-srcs">srcs</a>, <a href="#kernel_build-outs">outs</a>, <a href="#kernel_build-deps">deps</a>, <a href="#kernel_build-toolchain_version">toolchain_version</a>)
</pre>

Defines a kernel build target with all dependent targets.

It uses a build_config to construct a deterministic build environment (e.g.
`common/build.config.gki.aarch64`). The kernel sources need to be declared
via srcs (using a glob). outs declares the output files that are surviving
the build. The effective output file names will be
`$(name)/$(output_file)`. Any other artifact is not guaranteed to be
accessible after the rule has run. The default toolchain_version is defined
with a sensible default, but can be overriden.

Two additional labels, `{name}_env` and `{name}_config`, are generated.
For example, if name is `"kernel_aarch64"`:
- `kernel_aarch64_env` provides a source-able build environment defined by
  the build config.
- `kernel_aarch64_config` provides the kernel config.


### Parameters


**name** name {:#kernel_build-name}

 *Required.*  The final kernel target name, e.g. `"kernel_aarch64"`.

**build_config** build_config {:#kernel_build-build_config}

 *Required.*  Label of the build.config file, e.g. `"build.config.gki.aarch64"`.

**srcs** srcs {:#kernel_build-srcs}

 *Required.*  The kernel sources (a `glob()`).

**outs** outs {:#kernel_build-outs}

 *Required.*  The expected output files. For each item `out`:

  - If `out` does not contain a slash, the build rule
    automatically finds a file with name `out` in the kernel
    build output directory `${OUT_DIR}`.
    ```
    find ${OUT_DIR} -name {out}
    ```
    There must be exactly one match.
    The file is copied to the following in the output directory
    `{name}/{out}`

    Example:
    ```
    kernel_build(name = "kernel_aarch64", outs = ["vmlinux"])
    ```
    The bulid system copies `${OUT_DIR}/[<optional subdirectory>/]vmlinux`
    to `kernel_aarch64/vmlinux`.
    `kernel_aarch64/vmlinux` is the label to the file.

  - If `out` contains a slash, the build rule locates the file in the
    kernel build output directory `${OUT_DIR}` with path `out`
    The file is copied to the following in the output directory
      1. `{name}/{out}`
      2. `{name}/$(basename {out})`

    Example:
    ```
    kernel_build(
      name = "kernel_aarch64",
      outs = ["arch/arm64/boot/vmlinux"])
    ```
    The bulid system copies
      `${OUT_DIR}/arch/arm64/boot/vmlinux`
    to:
      - `kernel_aarch64/arch/arm64/boot/vmlinux`
      - `kernel_aarch64/vmlinux`
    They are also the labels to the output files, respectively.

    See `search_and_mv_output.py` for details.

**deps** deps {:#kernel_build-deps}

 *Optional.* *Default is* `()`.  

**toolchain_version** toolchain_version {:#kernel_build-toolchain_version}

 *Optional.* *Default is* `"r416183b"`.  The toolchain version to depend on.



