# `get_kernel_output`

The `OUT_DIR` is hided inside kleaf, unlike build.sh, we cannot get the path of `OUT_DIR`
before build system starting. Unfortunately, some of automatically debugging and
analyzing tools which need static `OUT_DIR` path would be broken.

`--get_kernel_output` is for compatibility with Linux build and build.sh build
which get `O`, a.k.a `OUT_DIR` in kleaf, easily and get everything unconditionally.

This is only for debugging or analyzing which would NOT affect any sandbox or caching
mechanism (e.g. config=local) in Bazel.

When the flag `--get_kernel_output=/target/path` is set, the `OUT_DIR` would be rsynced
to `/target/path` directory.

`/target/path` should be absolutely path only.


For example:

```shell
$ bazel build --get_kernel_output=/target/path //common:kernel_aarch64
```

You will find all the things inside `OUT_DIR` are rsynced to the `/target/path`
where `/target/path` is the destination with absolute path.
