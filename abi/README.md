ABI Monitoring for Android Common Kernels
=========================================

Overview
--------
This document describes the process of creating ABI representations for the
Kernel Module Interface of Android Common Kernels. The tooling is using the
"repo" approach to build the kernel and an abi-tool to extract and compare the
ABI information. The only abi-tool implementation for now is based on
[libabigail](https://sourceware.org/libabigail/). There might be different
implementations in the future.  

Process Description
-------------------
Analyzing the Kernel's ABI is done in multiple steps. Most of them can be
automated:

 1. Acquire the toolchain, build scripts and kernel sources through `repo`
 2. Provide any prerequisites (e.g. libabigail)
 3. Build the kernel
 4. Extract the ABI representation from the Kernel and the build modules
 5. Analyze the ABI differences between different kernel builds.

The instructions work for any kernel that can be built using the given
toolchain. There exist repo manifests for all Android Common Kernels as well as
for some upstream branches (e.g. upstream-linux-4.19.y).

For reference on how to acquire kernel sources and the toolchain with "repo" as
well as building, please refer to the building kernels section on
source.android.com. The project kernel/build that is downloaded during `repo
sync` contains all the resources to build kernels and the necessary tooling for
the ABI monitoring.<br>
A libabigail installation has to be provided by the host system and does not
(yet) come along with the tooling. Conveniently, there is a `bootstrap` script
part of the distribution that can be used to prepare all prerequisites including
building libabigail from source.

After having set up all prerequisites, collecting ABI information is done with
`build/build_abi.sh`. It will use `build/build.sh` to build the kernel (and
therefore accepts the same environment variables to customize the build) and
will create an *abi.xml* file in the `out` directory of the kernel build. This file
contains the ABI representation of the built kernel. If `ABI_DEFINITION` is set to
the location of an existing *abi.xml* within the kernel tree, `build_abi.sh` will
also attempt to compare the expected ABI representation with the actual one
extracted from the current build. In this case a file *abi.report* will be created
within the `dist` directory.

For analysis, the tool `build/abi/diff_abi` can be used to compare two ABI
representations with each other. It will create a report of all detected
differences for review.

More extensive documentation on the tooling can be found alongside the
kernel/build project in the ["abi" subdirectory](https://android.googlesource.com/kernel/build/+/refs/heads/master/abi/).

Please refer to the example usage below.

Example
-------
In this example we are using the Android Common 4.19 kernel branch to illustrate
the process of creating and comparing ABI representations.

First, set up the kernel build with "repo"

```
$ mkdir android-4.19 && cd android-4.19
$ repo init -u https://android.googlesource.com/kernel/manifest \
            -b common-android-4.19 \
            --depth=1
$ repo sync
```

In case the host system does not provide libabigail in a recent version (1.7 as
of today), use the `build/abi/bootstrap` script to build abigail from sources and
add the binary location to your `PATH`. The script will emit a command to do so
upon success:

```
$ build/abi/bootstrap
$ <execute the command bootstrap suggests to update your PATH>
```

Now build the kernel and create the ABI dump:

```
$ BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh
```

In this particular case, `build.config.gki.aarch64` describes a 'defconfig' build
with the provided prebuilt Clang.<br>
The ABI dump is created at `out/android-4.19/dist/abi-<id>.xml` and *abi.xml* is
symlinked to it. `id` is currently computed from `git describe` of the source
tree. In this case it boils down to just the commit id.

As an exercise, introduce an ABI breaking change, e.g.

```
diff --git a/include/linux/mm_types.h b/include/linux/mm_types.h
index 5ed8f6292a53..f2ecb34c7645 100644
--- a/include/linux/mm_types.h
+++ b/include/linux/mm_types.h
@@ -339,6 +339,7 @@ struct core_state {
 struct kioctx_table;
 struct mm_struct {
        struct {
+               int dummy;
                struct vm_area_struct *mmap;            /* list of VMAs */
                struct rb_root mm_rb;
                u64 vmacache_seqnum;                   /* per-thread vmacache */
```

and run `build_abi.sh` again.

```
$ BUILD_CONFIG=common/build.config.gki.aarch64 \
  SKIP_MRPROPER=1 SKIP_DEFCONFIG=1 SKIP_CP_KERNEL_HDR=1 \
  build/build_abi.sh
```

As the source tree has been modified, the abi dump file will be named like
`abi-<id>-dirty.xml`.

The abi changes between the two builds can now be generated with

```
$ build/abi/diff_abi \
     --baseline out/android-4.19/dist/abi-<id>.xml  \
     --new out/android-4.19/dist/abi-<id>-dirty.xml \
     --report abi-report.out
```

Kernel Branches with predefined ABI
-----------------------------------
Some Kernel branches might come with ABI representations as part of their source
distribution. These ABI representations are supposed to be accurate and should
reflect the result of `build_abi.sh` as if you would execute it on your own. As
the ABI is heavily influenced by various Kernel configuration options, these
.xml files usually belong to a certain configuration.<br>
E.g. the `common-android-mainline` branch contains an `abi_gki_aarch64.xml` that
corresponds to the build result when using the `build.config.gki.aarch64`. In
particular, the `build.config.gki.aarch64` also refers to this file as its
`ABI_DEFINITION`.

Such predefined ABI representations can be used as a baseline definition when
comparing with `diff_abi` (s.a.). E.g. to validate a Kernel patch in regards to
any changes to the ABI, create the ABI representation with the patch applied and
use `diff_abi` to compare it to the expected ABI for that particular source tree
/ configuration.

Caveats and known issues
------------------------
- Version 1.7 of libabigail, that contains all currently required patches to
  properly work on clang-built aarch64 Android Kernels has not been released
  yet. Using a recent master (at least from 16 June 2019) is a sufficient
  workaround for that.<br>
  The `bootstrap` script refers to a sufficient commit from upstream.

Document History
----------------

| Date      | Author   | Description                                       |
| --------- | -------- | ------------------------------------------------- |
|2019-03-29 | maennich | Initial draft.                                    | 
|2019-05-16 | maennich | Updated with more recent instructions             |
|2019-05-29 | maennich | abi dumps are stored as .xml                      |
|2019-05-29 | maennich | add "Kernel Branches with predefined ABI" section |
|2019-06-20 | maennich | Minor Updates                                     |

