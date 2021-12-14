# Kleaf Driver Development Kit (DDK)

**WARNING**: The DDK is currently a **work in progress**. Contents of this
document are subject to change.

## Objective

The Driver Development Kit (DDK) shall provide an easy way to develop Kernel
modules for GKI kernels. It should be suitable for new modules as well as for
existing modules and regardless of their location within the source tree.

## Requirements

* Support kernel module definitions for GKI kernels, possibly with reasonable
  migration steps.
* Ensure correct toolchain use (compilers, linkers, flags, etc.)
* Ensure correct visibility of resources provided by the GKI kernels (such as
  headers, Makefiles)
* Simple definition of kernel modules in one-place (avoiding separate definition
  locations)
* Unnecessary boilerplate (such as similarly looking Makefiles) generated during
  the make process.

## Background

With the introduction of the
[Generic Kernel Image (GKI)](https://preview.source.android.com/devices/architecture/kernel/generic-kernel-image)
, the deployment model for Android kernels has shifted from a monolithic kernel
per device that contains all necessary drivers to a generic kernel (centrally
released) for all devices and vendor-provided kernel modules to support
particular devices. Hence the development model changed for vendors: Any changes
to the core kernel need to be submitted to
[AOSP](https://android-review.googlesource.com/) for inclusion into the
[Android Common Kernels (ACK)](https://source.android.com/devices/architecture/kernel/android-common)
. **Drivers need to be developed as kernel modules**, matching the GKI interface
a.k.a.
[Kernel Module Interface (KMI)](https://docs.partner.android.com/partners/guides/gki/kmi-kernels)
. In order to do so, the correct build environment needs to be used, including
the correct toolchain as well as the correct resources provided by the GKI
kernel build, such as (generated)
headers and source files required to build kernel modules.

Traditionally, drivers were developed within the kernel tree as part of a
vendor- or device specific fork of the Android (common) kernel tree. While this
was practical at that time (in particular for monolithic kernels), it becomes
hard to maintain as now at least two trees need to be merged/maintained (the GKI
tree and the vendor tree that carries the specific drivers). Some prework on
mixed kernel builds has been done to support this two-tree situation, **yet
ideally modules would be kept entirely separate** from the core kernel tree.

Several partners have asked for a Driver Development Kit (DDK), Software
Development Kit (SDK) or therelike and it generally makes sense to have such for
when the kernel is standardized like it is with GKI. \
Often this is asked for as a minimal set of artifacts (headers, compilers, etc.)
. Whenever this discussion came up, there was consensus that reduction of size
of such a DDK matters, but given that the toolchain by far makes most of the
chunk, **not much can be done about reducing the size by just taking some source
files away**. Hence, considering a full kernel/manifest checkout is a reasonable
starting point for a DDK.

[Kleaf](kleaf.md) is the future way of building Android kernels. Kleaf is
replacing the existing [build/build.sh](../../build.sh)
scripts by a [Bazel](https://bazel.build/) build description. In particular, the
steps to build individual pieces of the kernel are (re-)implemented as Bazel (
starlark) rules to ensure they are executed in hermetic sandboxes with proper
**visibility** of the correct sources. As a significant side effect, Bazel is
allowed to parallelize the build and provides clever ways of **incrementally
building parts of the tree**. The DDK benefits from that: an incremental build
of a single module can be achieved much quicker as only the required rules get
invalidated and rebuilt (e.g. only the compilation and the link of a particular
module).

[Build descriptions for external kernel modules](https://www.kernel.org/doc/html/latest/kbuild/modules.html)
are often following the same schema: some source files, compilation flags,
defines, kconfig and dependencies to the kernel (headers) and other modules (
headers, possibly link time). Large parts of such **Makefiles could be
generated** based on provided information.

## Design ideas

Kernel module builds fundamentally follow the kernel build, from the build
definition to the timeliness that modules need to be built after the kernel
build has been done. Given the kernel build can be compiled with Kleaf today, I
propose we compile module builds with Kleaf, using the GKI kernel build as an
input. This model has been implemented for the Pixel 2021 kernel, wrapping the
module build invocations in the `kernel_module()`
Bazel macro for hermetic and parallel execution. See the following link for
details:

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

In order to build a kernel module with Kleaf, several steps have to be done:
Besides the sources, some files have to be authored to describe the module
build: Kbuild, Kconfig files, Makefiles. In addition, for Kleaf, a `BUILD.bazel`
file is used to embed the module build into the Kleaf build. All of the
mentioned files follow certain schemata or conventions and a lot of duplication
can be noticed across the tree. Yet, often very little information needs to be
actually provided: where are the source files? What flags, defines? What modules
should be produced? Dependencies between the modules? Configuration options?

I propose to entirely define the **module build with Bazel (starlark) macros**
within the BUILD.bazel file and **generate anything that is required to drive
the kernel module build** with Kbuild. Given the complexity of some modules, the
following interface will unlikely cover all use cases yet, but illustrates the
idea.

**WARNING**: The below example is for illustration only. Content is subject to
change.

```python
# BUILD.bazel
ddk_mod_config(
    name = "MYMOD",
)

ddk_module(
    name = "mymod",                            # produces mymod.ko
    srcs = ["ymod.c" "ymod_util.c" "ymod.h"],  # possibly glob()
    kernel = "//common:kernel_aarch64",        # the GKI kernel
    hdrs = ["ymod.h"],                         # visible to dependent modules
    configs = [":MYMOD"],                      # this simple case could be implicit
)

ddk_mod_config(
    name = "MY_OTHER_MOD",
      deps = [":MYMOD"],
)

ddk_mod_yesno_config(
    name = "SOME_OTHER_CONFIG",
    default = ""
)

ddk_module (
    name = "my_other_mod",                         # produces my_other_mod.ko
    srcs = ["y_other_mod.c"],
    kernel = "//common:kernel_aarch64",            # the GKI kernel
    deps = [":mymod"],
    configs = [":MY_OTHER_MOD", ":SOME_OTHER_CONFIG"],
)
```

In particular, the `kernel` parameter defines the kernel, it includes and the
toolchain. It does not matter where the kernel actually comes from (built from
sources or downloaded) in this case, as long as it provides all required
information for the module build.

Under the hood this will generate the corresponding kbuild files, stages them at
a hermetic location and builds them as usual as if they always have been an
external module with Makefile etc. Interesting to note is that **the location of
the module source files does not matter**. They could be part of a larger tree
or could be in separate repositories. The only requirement is that they are
within the Bazel _WORKSPACE_ (i.e. below the root directory).

Bazel files are **syntax checked at analysis time** and most subtle typing
errors will be caught early on. More useful: **dependency analysis is
comprehensive** and will quickly tell if dependencies are not satisfied. That
can be puzzling at times for developers with just Makefiles.

Many more details can be discussed of course, but let's see how this looks for
an example module.

## Example

The 
[NFC](go/aocs/android/kernel/superproject/+/gs-android-gs-raviole-mainline:gs/google-modules/nfc/)
modules of the P21 build serve as an example for the following. Looking at the
directory structure, we have

```
gs/google-modules/nfc
  ese/
      Makefile
      st33spi.c
      st54spi.c
  st21nfc.c
  st21nfc.h
  Makefile
  Kconfig
  BUILD.bazel
```

The source files obviously describe the functionality of the modules. The
definition of how the modules are built, how they are configured and how they
declare dependencies are scattered across 2 Makefiles, a Kconfig file and - now
with Kleaf - also extend to a BUILD.bazel file (shortened):

```makefile
# ese/Makefile:
	obj-$(CONFIG_ESE_ST54) += st54spi.o
	obj-$(CONFIG_ESE_ST33) += st33spi.o

# Makefile:
obj-$(CONFIG_NFC_ST21NFC)	+= st21nfc.o
	obj-$(CONFIG_ESE_ST54)		+= ese/
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
	M ?= $(shell pwd)
KBUILD_OPTIONS += CONFIG_NFC_ST21NFC=m CONFIG_NFC_ST21NFC_NO_CRYSTAL=y \
 				 CONFIG_ESE_ST54=m CONFIG_ESE_ST33=m
ccflags-y := -I$(KERNEL_SRC)/../google-modules/nfc
modules modules_install clean:
		$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) W=1 $(@)
```

```python
# BUILD.bazel:
kernel_module(
    name = "nfc.slider",
    srcs = glob([
        "**/*.c",
        "**/*.h"
        "ese/Makefile",
    ]),
    outs = [
        "ese/st33spi.ko",
        "ese/st54spi.ko",
        "st21nfc.ko",
    ],
    kernel_build = "//gs/kernel/device-modules:slider",
    visibility = [
        "//gs/kernel/device-modules:__pkg__",
    ],
)
```

But all that these files express is:

* take the kernel\_build `"//gs/kernel/device-modules:slider"`
* build a kernel module `st33spi.ko` out of `ese/st33spi.c`
* build a kernel module `st54spi.ko` out of `ese/st54spi.c`
* build a kernel module `st21nfc.ko` out of `st21nfc.c`
* the `st??spi.ko` modules have a build time dependency on the st21nfc headers
* some configuration options are defined and set

The Bazel definition for this module could be (and in terms of DDK that would be
the only thing required):

```python
# BUILD.bazel (some details omitted):
ddk_mod_config(
    name = "NFC_ST21NFC",
    deps = ["I2C"],
)
ddk_mod_yesno_config(
    name = "NFC_ST21NFC_NO_CRYSTAL",
    deps = ["NFC_ST21NFC"],
)

ddk_mod_config(
    name = "ESE_ST54",
    deps = ["SPI"],
)

ddk_mod_config(
    name = "ESE_ST33",
    deps = ["SPI"],
)

ddk_module(
    name = "st21nfc",
    srcs = ["st21nfc.c", "st21nfc.h"],
    hdrs = ["st21nfc.h"],
    configs = [":NFC_ST21NFC", ":NFC_ST21NFC_NO_CRYSTAL"],
    kernel = "//common:kernel_aarch64",
)
ddk_module(
    name = "st33spi",
    srcs = ["ese/st33spi.c"],
    configs = [":ESE_ST33"],
    deps = ["st21nfc"],
    kernel = "//common:kernel_aarch64",
)
ddk_module(
    name = "st54spi",
    srcs = ["ese/st54spi.c"],
    configs = [":ESE_ST54"],
    deps = ["st21nfc"],
    kernel = "//common:kernel_aarch64",
)
```

That would generate consistent `Makefiles`, `Kconfig` files, `Kbuild` files
during build time. In addition, it would take the complexity of toolchain
definitions etc. away.

## Configuration (`Kconfig` files)

By convention all modules come with a **configuration that corresponds to the
module**. That is to enable the feature they provide as either builtin or as a
module. While this is useful for in-tree modules, externally kept modules might
not need this explicit configuration or we can generate the configuration
according to the convention. For example, `CONFIG_NFC_ST21NFC` corresponds
to `st21nfc.ko`. We could generate the configuration based on that convention
and possibly avoid `ddk_mod_config` for most definitions.

## The DDK in practice

Developers that want to make use of the DDK need to start with a repo checkout
of the corresponding ACK, e.g. common-android-mainline. They will need to add
their module sources as additional repositories and will need to add BUILD.bazel
files accordingly.

The first build will indeed build the actual GKI kernel before building the
local modules. Any subsequent changes to only modules will then use a cached
version of the kernel build, thanks to Bazels caching. This will reduce the
turnaround time for module developers and will only require one full kernel
build whenever the build tools or the kernel sources change.

The kernel build as part of the DDK has a practical component as well. At times,
developers need to interact with the GKI kernel code: adding vendor hooks,
updating KMI, backporting upstream patches. In those cases the kernel will be
built entirely and the result serves as an input for the module build (i.e. the
new version of the DDK). That simplifies contributions to ACK as the result can
be built and tested end-to-end in just the DDK checkout locally.

## On visibility

This design suggests `//common:kernel_aarch64` as an input for the modules and
that (as of today) means the entire GKI kernel build and its sources are
considered inputs. In particular that makes all build artifacts visible for
module builds and all headers. Using the visibility mechanisms from Bazel we can
reduce the visibility of the artifacts to limit what a module build can consume.
E.g. we can allow-list header files that should be visible when doing module
builds (such as only `include/linux/` or `arch/$(ARCH)/include/` and
not `drivers/`) by still enforcing that they come from the right location (the
GKI kernel). One way of doing that is to define a filegroup in the GKI
definition as a subset of the kernel sources.

**At a later stage we can switch the `kernel` input to a smaller subset to
reduce on disk space for the DDK.** As long as the interface for `ddk_module()`
and friends is still satisfied and toolchain and module build resources are
provided.
