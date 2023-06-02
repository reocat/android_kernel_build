# Internet Access

Bazel has the ability to download repositories from the internet if explicitly
requested to do so, or if it doesi not find a dependency during its setup and
there it is set an external repository where to download it from.

To avoid surprising behaviours, Kleaf has introduced two build configs to
control this access (`--config=internet` and `--config=no_internet`).

In a near future, `--config=no_internet` will be set by default, disabling
external downloads, except when using
[`--use_prebuilt_gki`](download_prebuilt.md#step-2_build-with).

Developers will be able to re-enable internet access via `--config=internet`,
for example:

```shell
tools/bazel build //build/kernel/kleaf:docs --config=internet
```
