# Kleaf - Building Android Kernels with Bazel

**Note:** THIS IS EXPERIMENTAL AND INCOMPLETE. USE WITH CAUTION!

## Background

The canonical way of
[building](https://source.android.com/setup/build/building-kernels) Android
Kernels is currently using
[`build/build.sh`](https://android.googlesource.com/kernel/build/+/refs/heads/master/build.sh).
While stabilized, `build/build.sh` exposes issues to users, kernel engineers and
kernel build engineers that are hard to resolve within the current
implementation. Hence, alternative ways of building Android Kernels are
researched. This project is attempting to implement Android Kernel builds with
[Bazel](https://bazel.build/) while providing all relevant features that
`build/build.sh` made so well accepted in the Android ecosystem. Bazel is
choosen as the
[future build system for the Android platform](https://opensource.googleblog.com/2020/11/welcome-android-open-source-project.html).

## Using Kleaf

As of today, kleaf is not yet supporting the same feature set as
`build/build.sh`. Nevertheless, some targets can be used and tried out. In
particular this might be helpful to evaluate any future infrastructure
integrations.

### Prerequistes

There are no additional host dependencies. The Bazel toolchain and environment
are provided through `repo sync` as per definition in the kernel manifests. As a
convenience, installing a `bazel` host package allows using the `bazel` command
from anywhere in the tree (as opposed to using `tools/bazel` from the top of the
workspace).

### Running a build

Android Common Kernels define at least a 'kernel' rule as part of the build
definition in the `common/` subdirectory. Building just a kernel is therefore as
simple as

```
 $ tools/bazel build //common:kernel
```

With a `bazel` host side package, this reduces to

```
 $ bazel build //common:kernel
```

and this command can be executed from any subdirectory below the top level
workspace directory.

`//common:kernel` is by convention referring to the default kernel target and in
case of Android Common Kernels
([GKI](https://preview.source.android.com/devices/architecture/kernel/generic-kernel-image)),
this will usually be an alias for `kernel_aarch64`. Further targets can be
discovered via bazel's query mechanisms:

```
 $ bazel query "kind('genrule', //common:*)"
```

## Build definitions

In order to define an own build, for example in your own (downstream) tree, use
the `kernel_build` macro provided by this package. The simplest example is
(defining the GKI build):

```
load("//build/kleaf:kernel.bzl", "kernel_build")

kernel_build(
    name = "kernel",
    outs = ["vmlinux"],
    build_config = "common/build.config.gki.aarch64",
    sources = glob(["**"]),
)
```

Running `bazel build kernel` is then comparable with the equivalent
`build/build.sh` invocation (limited to the current available features in
kleaf):

```
BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
```

## Availability

For now, Kleaf is planned to made available for Android 13 and later kernels.
That is as of writing `android13-5.10` and `android-mainline`. During
development, `android-mainline` will usually work, while `android13-5.10` might
occasionally be broken or missing latest backports.

## FAQ

**Question:** How can I try it?

Answer: With a recent `repo` checkout of `common-android-mainline`, the simplest
invocation is `tools/bazel build //common:kernel`.

**Question:** Are `BUILD_CONFIG` files still a thing?

Answer: Yes! `build.config` files still describe the build environment. Though
they get treated as hermetic input. Further, some features might not be
supported yet or never will be as they do not make sense in a bazel based build
(e.g. `SKIP_MRPROPER` is implicit in baze based builds).

**Question:** When will it be available?

Answer: Plans are to support Bazel based Android Kernel builds with Android 13,
that is on `android13-*` or later kernel branches.

**Question:** Why "Kleaf"?

Answer: Occasionally, the Android Platform Build with Bazel is referred to as
Roboleaf (Robo=Android, Bazel...Basil...Leaf). The kernel variant of that is
Kleaf, K referring to the Kernel.
