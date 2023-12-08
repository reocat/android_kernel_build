# Bzlmod support for Kleaf


## Versions of dependent modules

### Cheatsheet

```text
bazel_dep version == single_version_override version == local BCR version <= actual version in external/
```

### bazel\_dep version

This refers to the version of a given module declared in `bazel_dep` in [MODULE.bazel](MODULE.bazel).

This is the version that `@kleaf` expects from the dependent module. For
example, if `@kleaf` uses feature A from `rules_cc@1.5`, then the `bazel_dep`
declaration should have at least `rules_cc@1.5`.

In theory, only the following constraint is needed so that `@kleaf` functions
properly:

```text
bazel_dep version <= single_version_override version
```

In practice, the following stricter constraint is used when the local registry
is updated in order to avoid confusion of inconsistent values.

```text
bazel_dep version == single_version_override version
```

### single\_version\_override version

This refers to the pinned version used at build time. Refer to the definition
[here](https://bazel.build/rules/lib/globals/module#single_version_override).

At build time, Bazel looks up the version declared in `single_version_override`
from the registry, and resolve accordingly.

**Note**: `single_version_override` statements are ignored when `@kleaf` is used
as a dependent module of the root module.

This must equal the local BCR version. See reasons below.

### local BCR version

For a given module, this is the version with `"type": "local"` under
`external/bazelbuild-bazel-central-registry`.

This must equal `single_version_override`. At build time, Bazel looks up the
version declared in `single_version_override` from the registry. The registry
always declare `"type": "local"` and `"path": "external/<module_name>` for
that version. Then, the module at that version is vendored through
`external/<module_name>`.

### actual version in external/

For a given module, this is the version declared in
`external/<module_name>/MODULE.bazel`, with a few exceptions.

This is the actual version of the dependency. But at build time, Bazel does not
care about the actual version. Because of
[backwards compatibility guarantees](https://bazel.build/external/module#compatibility_level)
when compatibility level is the same, it is okay to use a new version as an
old version.

Usually, the following holds true:

```text
local BCR version == actual version in external/
```

However, if the external Git repository is updated indenpendently, there may
be a period of time where `local BCR version < actual version in external/`,
until `external/bazelbuild-bazel-central-registry` has `source.json` updated
for that module.

## See also

[https://bazel.build/external/module](Bazel modules)
