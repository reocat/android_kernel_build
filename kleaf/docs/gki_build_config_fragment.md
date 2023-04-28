# Supporting GKI\_BUILD\_CONFIG\_FRAGMENT on Kleaf

The **debug** option `--gki_build_config_fragment` allow developers to use a
build config fragment to modify/override the GKI build config for debugging
purposes.

The following is a no-op example of how to use it.

```shell
tools/bazel build //common:kernel_aarch64 --gki_build_config_fragment="//build/kernel/kleaf/impl:empty_filegroup"
```

In practice a developer will need to provide the target containing the
fragment(s) to be used. For example if the fragment is
`build.config.gki.sample.fragment`, the following
[filegroup](https://bazel.build/reference/be/general#filegroup) can be used:

```shell
filegroup(
    name = "sample_gki_config",
    srcs = [
        "build.config.gki.sample.fragment",
    ],
)
```

then assuming the **ACK** is located at `//common` the command to run would be:

```shell
tools/bazel build //common:kernel_aarch64 --gki_build_config_fragment="//common:sample_gki_config"
```
