# `GCOV`

When the flag `--gcov` is set, the build is reconfigured to produce (and keep)
`*.gcno` files.

For example:

```shell
$ bazel build --gcov //common:kernel_aarch64
```

You may find the `*.gcno` files under the
`bazel-bin/<package_name>/<target_name>/gcno` directory,
where `<target_name>` is the name of the `kernel_build()`
macro. In the above example, the `.gcno` files can be found at

```
bazel-bin/common/kernel_aarch64/gcno/
```

## Handling path mapping

After you boot up the kernel and [mount debugfs](https://docs.kernel.org/filesystems/debugfs.html):

```shell
$ mount -t debugfs debugfs /sys/kernel/debug
```

You may see gcno files under:

```
/sys/kernel/debug/gcov/<some_host_absolute_path_to_repository>/<some_out_directory>/common/<some_source_file>.gcno
```

To map between these paths to the host, consult the `gcno/mapping.json`
under `bazel-bin/`. In the above example, the file can be found in

```
bazel-bin/common/kernel_aarch64/gcno/mapping.json
```

Sample content of `gcno/mapping.json`:

```json
[
  {
    "from": "/<some_host_absolute_path_to_repository>/<some_out_directory>",
    "to": "."
  }
]
```

The JSON file contains a list of mappings. Each mapping indicates that `/sys/kernel/debug/<from>`
on the device maps to `<to>` on host.

**Note**: For both `<from>` and `<to>`, absolute paths should be interpreted as-is,
and relative paths should be interpreted as relative to the repository on host. For example:

```json
[
  {
    "from": "/absolute/from",
    "to": "/absolute/to"
  },
  {
    "from": "relative/from",
    "to": "relative/to"
  }
]
```

This means:
* Device `/sys/kernel/debug/absolute/from` maps to host `/absolute/to`
* Device `/sys/kernel/debug/<repositry_root>/relative/from` maps to host `/<repository_root>/relative/to`.
