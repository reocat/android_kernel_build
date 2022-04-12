# Supporting ABI monitoring with Bazel

## ABI monitoring for GKI builds

### Update symbol list

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update_symbol_list
```

This updates `kmi_symbol_list` of `//common:kernel_aarch64`, which is
typically `common/android/abi_gki_aarch64`.


### Update ABI definition

**Note**: You must [update the symbol list](#update-symbol-list) first. The
Bazel command below does not update the source symbol list, unlike
the `build_abi.sh` command.

**Note**: The Bazel command alone does **NOT** compare ABI. See
[build dist artifacts](#build-dist-artifacts) below.

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update
```

This updates `abi_definition` of `//common:kernel_aarch64`, which is
typically `common/android/abi_gki_aarch64.xml`.


### Build dist artifacts

```shell
$ tools/bazel run //common:kernel_aarch64_abi -- --dist_dir=out/dist
```

This compares ABI and generates a diff report. This also builds all ABI-related
artifacts for distribution, and copies to the given directory.

### Convert from `build_abi.sh`

Here's a table for converting `build_abi.sh`
into Bazel commands, assuming `BUILD_CONFIG=common/build.config.gki.aarch64`
for `build_abi.sh`.

```shell
# build_abi.sh --update_symbol_list
# Update symbol list [1]
$ tools/bazel run kernel_aarch64_abi_update_symbol_list

# build_abi.sh --nodiff
# Extract the ABI (but do not compare it) [2]
$ tools/bazel build kernel_aarch64_abi_dump

# build_abi.sh --nodiff --update
# Update symbol list, [1][3]
$ tools/bazel run kernel_aarch64_abi_update_symbol_list &&
# Extract the ABI (but do not compare it), then update `abi_definition` [2][3]
> tools/bazel run kernel_aarch64_abi_update

# build_abi.sh --update
# Update symbol list, [1][3]
$ tools/bazel run kernel_aarch64_abi_update_symbol_list &&
# Extract the ABI and compare it, [2][3][4]
> tools/bazel build kernel_aarch64_abi &&
# then update `abi_definition` [3][4]
> tools/bazel run kernel_aarch64_abi_update

# build_abi.sh
# Extract the ABI and compare it [2]
$ tools/bazel build kernel_aarch64_abi

# build_abi.sh
# Extract the ABI and compare it, then copy artifacts to `--dist_dir`
$ tools/bazel run kernel_aarch64_abi_dist -- --dist_dir=...
```

Notes:

1. The command updates `kmi_symbol_list` but it does not update
  `$DIST_DIR/abi_symbollist`, unlike the `build_abi.sh --update-symbol-list`
  command.
2. The Bazel command extracts the ABI and/or compares the ABI like the
   `build_abi.sh` command, but it does not copy the ABI dump and/or the diff
   report to `$DIST_DIR` like the `build_abi.sh` command. You may find the
   ABI dump in Bazel's output directory under `bazel-bin/`.
3. Order matters, and the two commands cannot run in parallel. This is
   because updating the ABI definition requires the **source**
   `kmi_symbol_list` to be updated first.
4. The behavior of `build_abi.sh --update` is that the ABI definition is
   updated regardless of the comparison result. This is not the case in this
   particular Bazel command. You can ignore the result of comparison by
   ignoring the exit code of the second command, 
   `tools/bazel build kernel_aarch64_abi`, and running the third command
   `tools/bazel run kernel_aarch64_abi_update` unconditionally.
