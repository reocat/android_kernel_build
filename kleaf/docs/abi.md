# Supporting ABI monitoring with Bazel

## ABI monitoring for GKI builds

### Build kernel and ABI artifacts

```shell
$ tools/bazel run //common:kernel_aarch64_abi_dist
```

This compares the ABI and generates a diff report. This also builds all
ABI-related artifacts for distribution, and copies them to the given directory.
The exit code reflects whether an ABI change is detected in the comparison, just
like `build_abi.sh`.

### Update symbol list

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update_symbol_list
```

This updates `kmi_symbol_list` of `//common:kernel_aarch64`, which is
`common/android/abi_gki_aarch64`.

### Extracting the ABI

```shell
$ tools/bazel build //common:kernel_aarch64_abi_dump
```

This command extracts the ABI, but does not compare it. This is similar to
`build/build_abi.sh --nodiff`.

### Update the ABI definition

**Note**: You must [update the symbol list](#update-symbol-list) first. The
Bazel command below does not update the source symbol list, unlike
the `build_abi.sh` command.

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update
```

This compares the ABI, then updates the `abi_definition`
of `//common:kernel_aarch64`, which is `common/android/abi_gki_aarch64.xml`. The
exit code reflects whether an ABI change is detected in the comparison, just
like `build_abi.sh --update`.

If you do not wish to compare the ABI before the update, you may execute the
following instead:

```shell
$ tools/bazel run //common:kernel_aarch64_abi_nodiff_update
```

### Convert from `build_abi.sh`

Here's a table for converting `build_abi.sh`
into Bazel commands, assuming `BUILD_CONFIG=common/build.config.gki.aarch64`
for `build_abi.sh`.

**NOTE**: It is recommended to run these commands with `--config=local` so
`$OUT_DIR` is cached, similar to how `build_abi.sh` sets `SKIP_MRPROPER`. See
[sandbox.md](sandbox.md) for more details.

**NOTE**: Executing `build_abi.sh` with the arguments also tries to provide an
equivalent Bazel command for you, so you don't have to look it up here.

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
> tools/bazel run kernel_aarch64_abi_nodiff_update

# build_abi.sh --update
# Update symbol list, [1][3]
$ tools/bazel run kernel_aarch64_abi_update_symbol_list &&
# Extract the ABI and compare it, then update `abi_definition` [2][3]
> tools/bazel run kernel_aarch64_abi_update

# build_abi.sh
# Extract the ABI and compare it, then copy artifacts to distribution directory
$ tools/bazel run kernel_aarch64_abi_dist
```

Notes:

1. The command updates `kmi_symbol_list` but it does not update
   `$DIST_DIR/abi_symbollist`, unlike the `build_abi.sh --update-symbol-list`
   command.
2. The Bazel command extracts the ABI and/or compares the ABI like the
   `build_abi.sh` command, but it does not copy the ABI dump and/or the diff
   report to `$DIST_DIR` like the `build_abi.sh` command. You may find the ABI
   dump in Bazel's output directory under `bazel-bin/`.
3. Order matters, and the commands cannot run in parallel. This is because
   updating the ABI definition requires the **source**
   `kmi_symbol_list` to be updated first.
