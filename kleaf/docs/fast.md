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

**WARNING**: Due to
[Issue 15679](https://github.com/bazelbuild/bazel/issues/15679), specifying
`--lto` in the command line does not take effect with `--config=fast`
as of 2022-06-15. Consider using `--config=local` until the issue is resolved.
For example:

```shell
# DO NOT USE: --lto may be set to thin due to Issue 15679
# tools/bazel run --config=fast --lto=none //common:kernel_dist

# Instead, use:
$ tools/bazel run --config=local --lto=none //common:kernel_dist
```

You may build the following to confirm the value of LTO setting:

```shell
$ tools/bazel build [flags] //build/kernel/kleaf:print_flags
```

## Local cache dir

Building with `--config=fast` implies `--config=local` for some rules, such as
the `kernel_build` rule. The `local` mode makes use of a persistent `$OUT_DIR`
across invocations to cache the rule execution state. The default cache
directory is `$WORKSPACE/out/cache`, but can be overridden by passing
`--cache_dir=/some/fast/disk` in order to make use of a file system that
performs well or better for the kernel build workload. Full example:

```shell
$ tools/bazel run --config=fast //common:kernel_aarch64 --cache_dir=/some/fast/disk -- --dist_dir=out/dist
```
