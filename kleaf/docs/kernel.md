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


**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :-------------: | :-------------: | :-------------: | :-------------: | :-------------: |
| name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| kernel_build |  Label referring to the kernel_build module   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| kernel_module_deps |  A list of other kernel_module dependencies   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |
| makefile |  Label referring to the makefile. This is where "make" is executed on ("make -C $(dirname ${makefile})").   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | optional | None |
| outs |  the expected output files. For each token <code>out</code>, the build rule automatically finds a file named <code>out</code> in the legacy kernel modules staging directory. The file is copied to the output directory of this package, with the label <code>out</code>.<br><br>- If <code>out</code> doesn't contain a slash, subdirectories are searched.<br><br>  Example:   <pre><code>   kernel_module(name = "nfc", outs = ["nfc.ko"])   </code></pre><br><br>  The build system copies     <code>&lt;legacy modules staging dir&gt;/lib/modules/*/extra/&lt;some subdir&gt;/nfc.ko</code>   to     <code>&lt;package output dir&gt;/nfc.ko</code>.   <code>nfc.ko</code> is the label to the file.<br><br>- If {out} contains slashes, its value is used. The file is also copied   to the top of package output directory.<br><br>  For example:   kernel_module(name = "nfc", outs = ["foo/nfc.ko"])<br><br>  The build system copies     <code>&lt;legacy modules staging dir&gt;/lib/modules/*/extra/foo/nfc.ko</code>   to     <code>foo/nfc.ko</code>.   <code>foo/nfc.ko</code> is the label to the file.<br><br>  The file is also copied to     <code>&lt;package output dir&gt;/nfc.ko</code>.   <code>nfc.ko</code> is the label to the file.   See <code>search_and_mv_output.py</code> for details.   | List of labels | optional | None |
| srcs |  source files to build this kernel module   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | required |  |


<a name="#kernel_build"></a>

## kernel_build

<pre>
kernel_build(<a href="#kernel_build-name">name</a>, <a href="#kernel_build-build_config">build_config</a>, <a href="#kernel_build-srcs">srcs</a>, <a href="#kernel_build-outs">outs</a>, <a href="#kernel_build-deps">deps</a>, <a href="#kernel_build-toolchain_version">toolchain_version</a>)
</pre>

Defines a kernel build target with all dependent targets.

   It uses a build_config to construct a deterministic build environment
   (e.g. `common/build.config.gki.aarch64`). The kernel sources need to be
   declared via srcs (using a glob). outs declares the output files
   that are surviving the build. The effective output file names will be
   `$(name)/$(output_file)`. Any other artifact is not guaranteed to be
   accessible after the rule has run. The default toolchain_version is
   defined with a sensible default, but can be overriden.

   Two additional labels, `{name}_env` and `{name}_config`, are generated.
   For example, if name is `"kernel_aarch64"`:
   - `kernel_aarch64_env` provides a source-able build environment defined
     by the build config.
   - `kernel_aarch64_config` provides the kernel config.


**PARAMETERS**


| Name  | Description | Default Value |
| :-------------: | :-------------: | :-------------: |
| name |  the final kernel target name, e.g. <code>"kernel_aarch64"</code>   |  none |
| build_config |  the path to the build config from the directory containing    the WORKSPACE file, e.g. <code>"common/build.config.gki.aarch64"</code>   |  none |
| srcs |  the kernel sources (a <code>glob()</code>)   |  none |
| outs |  the expected output files. For each item <code>out</code>:<br><br>  - If <code>out</code> does not contain a slash, the build rule     automatically finds a file with name <code>out</code> in the kernel     build output directory <code>${OUT_DIR}</code>.     <pre><code>     find ${OUT_DIR} -name {out}     </code></pre>     There must be exactly one match.     The file is copied to the following in the output directory     <code>{name}/{out}</code><br><br>    Example:     <pre><code>     kernel_build(name = "kernel_aarch64", outs = ["vmlinux"])     </code></pre>     The bulid system copies <code>${OUT_DIR}/[&lt;optional subdirectory&gt;/]vmlinux</code>     to <code>kernel_aarch64/vmlinux</code>.     <code>kernel_aarch64/vmlinux</code> is the label to the file.<br><br>  - If <code>out</code> contains a slash, the build rule locates the file in the     kernel build output directory <code>${OUT_DIR}</code> with path <code>out</code>     The file is copied to the following in the output directory       1. <code>{name}/{out}</code>       2. <code>{name}/$(basename {out})</code><br><br>    Example:     <pre><code>     kernel_build(       name = "kernel_aarch64",       outs = ["arch/arm64/boot/vmlinux"])     </code></pre>     The bulid system copies       <code>${OUT_DIR}/arch/arm64/boot/vmlinux</code>     to:       - <code>kernel_aarch64/arch/arm64/boot/vmlinux</code>       - <code>kernel_aarch64/vmlinux</code>     They are also the labels to the output files, respectively.<br><br>    See <code>search_and_mv_output.py</code> for details.   |  none |
| deps |  <p align="center"> - </p>   |  <code>()</code> |
| toolchain_version |  the toolchain version to depend on   |  <code>"r416183b"</code> |


