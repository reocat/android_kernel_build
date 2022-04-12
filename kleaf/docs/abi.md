# Supporting ABI monitoring with Bazel

## ABI monitoring for GKI builds

### Update symbol list

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update_symbol_list
```

This updates `kmi_symbol_list` of `//common:kernel_aarch64`, which
is typically `common/android/abi_gki_aarch64`.

Rule of thumb:

```
  BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh --update_symbol_list
=>
  tools/bazel run      //common:kernel_aarch64[..........]_abi[...]_update_symbol_list
```

### Update ABI definition

**Note**: You must [update the symbol list](#update-symbol-list) first. The
Bazel command below does not update the source symbol list, unlike
the `build_abi.sh` command.

**Note**: The Bazel command alone does **NOT** compare ABI. See 
[build dist artifacts](#build-dist-artifacts) below.

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update
```

This updates `abi_definition` of `//common:kernel_aarch64`, which
is typically `common/android/abi_gki_aarch64.xml`.

Rule of thumb:

```
  BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh --update
=>
  tools/bazel run      //common:kernel_aarch64[..........]_abi[...]_update
```

### Build dist artifacts

```shell
$ tools/bazel run //common:kernel_aarch64_abi -- --dist_dir=out/dist
```

This compares ABI and generates a diff report. This also builds all 
ABI-related artifacts for distribution, and copies to the given directory.

Rule of thumb:

```
  BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh
=>
  tools/bazel run      //common:kernel_aarch64[..........]_abi_dist -- ...
```

**Note** for non-ABI builds:

```
  BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
=>
  tools/bazel run      //common:kernel_aarch64[..........]_dist     -- ...
```
