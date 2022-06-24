# kasan

To build with kasan enabled, add the `--kasan` flag. Example:

```shell
$ tools/bazel run --kasan //common:kernel_aarch64_dist
```

Kasan builds automatically disables LTO by setting it to `none`. If `--lto` is
explicitly specified, it must be set to `none`, otherwise build fails.

## Interaction with `--config=fast`

`--config=fast` specifies `--lto=thin`, which is not allowed by `--kasan`. If
you want to disable some sandboxes to make incremental build faster,
use `--config=local` instead. For example:

```shell
$ tools/bazel run --kasan --config=local //common:kernel_aarch64_dist
```

## Confirming the value of `--kasan`

You may build the following to confirm the value of kasan setting:

```shell
$ tools/bazel build [flags] //build/kernel/kleaf:print_flags
```

Note: the value of `--lto` reflects the value specified in the command line,
which may show `default` or `none`. However, if `--kasan` is specified,
`--lto` is coerced into `none`, no matter if it is specified in the command
line.

## See also

[LTO](lto.md)

[Sandboxing](sandbox.md)
