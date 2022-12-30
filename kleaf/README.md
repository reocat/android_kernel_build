# Kleaf - Building Android Kernels with Bazel

## Table of contents

[Introduction to Kleaf](docs/kleaf.md)

[Building your kernels and drivers with Bazel](docs/impl.md)

[`build.sh` build configs](docs/build_configs.md)

[Running `make *config`](docs/kernel_config.md)

[Support ABI monitoring (GKI)](docs/abi.md)

[Support ABI monitoring (Device)](docs/abi_device.md)

[Handling SCM version](docs/scmversion.md)

[Resolving common errors](docs/errors.md)

[References to Bazel rules and macros for the Android Kernel](https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html)

[Kleaf testing](docs/testing.md)

[Building against downloaded prebuilts](docs/download_prebuilt.md)

[Customize workspace](docs/workspace.md)

[Cheatsheet](docs/cheatsheet.md)

[Kleaf Development](docs/kleaf_development.md)

### Configurations

`--config=fast`: [Make local builds faster](docs/fast.md)

`--config=local`: [Sandboxing](docs/sandbox.md)

`--config=release`: [Release builds](docs/release.md)

`--config=stamp`: [Handling SCM version](docs/scmversion.md)

`--gcov`: [Keep GCOV files](docs/gcov.md)

`--kasan`: [kasan](docs/kasan.md)

`--kbuild_symtypes`: [KBUILD\_SYMTYPES](docs/symtypes.md)

`--kgdb`: [GDB scripts](docs/kgdb.md)

`--lto`: [Configure LTO during development](docs/lto.md)

### Debugging options

The following flags are provided as a way to help debugging compilation issues,
use them according to your needs.

`debug_annotate_scripts`: allows to run all script invocations with `set -x` and a
 trap that executes `date` after every command.

`debug_make_verbosity`: flag to control `make` verbosity `E (default) = Error, I =
Info, D = Debug`

`debug_modpost_warn`: If true, set [`KBUILD\_MODPOST\_WARN=1`](https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-modpost-warn).

`debug_print_scripts`: Running the build with bazel build
`--debug_print_scripts <target>` will print the runtime scripts during
 rule execution.

