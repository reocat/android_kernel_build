# Build faster

## TL;DR

For local developing workflow, build with `--config=fast`.

Example:

```shell
$ tools/bazel run --config=fast //common:kernel_aarch64 -- --dist_dir=out/dist
```

Or add to `user.bazelrc`:

```text
# user.bazelrc
build --config=fast
```

## How does this work?

This config implies:

- `--lto=thin`. See [LTO](#lto).
- `--config=local`. See [sandbox.md](sandbox.md).
- `--disable_btf_info`. See [BTF debug information](#btf-debug-information).

## LTO

By default, `--config=fast` implies `--lto=thin`. If you want to specify
otherwise, you may override its value in `user.bazelrc`, e.g.

```text
# user.bazelrc

# When `--config=fast` is set, disable LTO
build:fast --lto=none

# When no config is set, disable LTO
build --lto=none
```

**NOTE**: If you are using `--lto` with `--config=fast`, `--lto` must be
specified after `--config=fast` because flags specified later take
precedence. If unsure, use `--config=local` instead. For example:

```shell
# CORRECT:
$ tools/bazel run --config=fast --lto=none //common:kernel_dist

# CORRECT:
$ tools/bazel run --config=local --lto=none //common:kernel_dist

# WRONG: --lto is set to thin
# tools/bazel run --lto=none --config=fast //common:kernel_dist
```

You may build the following to confirm the value of LTO setting:

```shell
$ tools/bazel build [flags] //build/kernel/kleaf:print_flags
```

## BTF debug information

Option `--disable_btf_info` **disables** generation of BTF debug information.

This information is useful in release binaries to allow debugging BPF programs.
But it requires a lot of time to be generated.

If you need fast build *and* BTF debug information, you can replace
`--config=fast` with separate options like `--lto=thin --config=local` without
including `--disable_btf_info`.
