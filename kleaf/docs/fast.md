# Build faster

## TL;DR

For local developing workflow, build with `--config=fast`:

```shell
$ tools/bazel --config=fast run //common:kernel_aarch64 -- --dist_dir=out/dist
```

This config implies:

- [Thin LTO](#lto)
- [`--strategy ...=local` for various actions](#no-sandboxes)
- [Skipping SCM version](#scm-version)

## LTO

By default, `--config=fast` implies `--lto=thin`. If you want to specify
otherwise, you may override its value in the command line or in `user.bazelrc`,
e.g.

```shell
$ tools/bazel --config=fast --lto=none run //common:kernel_aarch64 -- --dist_dir=out/dist
```

```text
# user.bazelrc
build:fast --lto=none
```

You may build the following to confirm the value of LTO setting:

```shell
$ tools/bazel build //build/kernel/kleaf:lto_print
```

## No sandboxes

By default, all [actions](https://bazel.build/reference/glossary#action) runs
within a sandbox. Sandboxes ensures hermeticity, but also introduced extra
overhead at build time:

- Creating the sandbox needs time, especially when there are too many inputs
- Using sandboxes disallows caching of `$OUT_DIR`

To overcome this and boost build time, a few types of actions are executed
without the sandbox when `--config=fast`. The exact list of types of actions are
an implementation detail. If other types of actions were executed without the
sandbox, they might interfere with each other when executed in parallel.

When building with `--config=fast`, `$OUT_DIR` is cached. This is approximately
equivalent to building with `SKIP_MRPROPER=1 build/build.sh`.

To clean the cache, run

```shell
$ tools/bazel clean
```

**NOTE**: It is recommended to execute `tools/bazel clean` whenever you switch
from and to `--config=fast`. Otherwise, you may get surprising cache hits or
misses because changing `--strategy` does **NOT** trigger rebuilding of an
action.

## SCM version

See [scmversion.md](scmversion.md) for context of SCM version.

Handling SCM version properly creates some overhead for almost every 
meaningful `bazel` commands via `--workspace_status_command`; see documentation
[here](https://bazel.build/reference/command-line-reference#flag--workspace_status_command).

Hence, SCM versions are not embedded when `--config=fast`.
