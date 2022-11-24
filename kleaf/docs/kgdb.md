# GDB scripts

To enable `CONFIG_GDB_SCRIPTS` and collect the scripts, enable the `--kgdb`
flag.

The scripts may be found under `bazel-bin/<package>/<target_name>/gdb_scripts`.

## Additional hacks to enable GDB scripts

Sometimes, along with `CONFIG_GDB_SCRIPTS`, a device requires additional hacks
to make debugging possible. These hacks may include:

- Disabling mixed build
- Using additional defconfigs

To do so:

- If a different build config or defconfig is needed, put it in a separate
  `build.config` file.
- In `BUILD.bazel`, use `select()` to differentiate the behavior based on
  `//build/kernel/kleaf:kgdb_set`.

For details about `select()`, see
[Configurable Build Attributes](https://bazel.build/docs/configurable-attributes)
.

## Example

Example CL for the virtual device:

(kleaf: enable kgdb
builds)[https://android-review.git.corp.google.com/c/kernel/common-modules/virtual-device/+/2315864]

In this example, you may build with:

```shell
tools/bazel build //common-modules/virtual-device:virtual_device_x86_64 --kgdb
```

When `--kgdb` is set, the alias
`//common-modules/virtual-device:virtual_device_x86_64` resolves to
`//common-modules/virtual-device:virtual_device_x86_64_kgdb`, so you may find
the scripts under
`bazel-bin/common-modules/virtual-device/virtual_device_x86_64_kgdb/gdb_scripts`
.