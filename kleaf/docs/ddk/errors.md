# Resolving common errors for the DDK

## Table of contents

[Generic steps for resolving missing header](#missing-headers)

[Missing include/linux/compiler-version.h](#missing-compiler-version-h)

[Missing include/linux/kconfig.h](#missing-compiler-version-h)

## `<source>.c:<line>:<col>: fatal error: '<header>.h file not found` {#missing-headers}

Resolving errors about missing headers can be tough. In general, debugging these
errors involve the following steps:

1. Check where the requested header is
2. Check all of the include directories of the DDK module
3. Add the requested header and necessary include directories to the module

### Find a certain header with the given name

This step is straightforward with a `find(1)` command. Example: if the error is

```text
#include <linux/i2c.h>
         ^~~~~~~~~~~~~
```

Then you can look for it with

```shell
$ find . -path "*/linux/i2c.h"
./common/include/uapi/linux/i2c.h
[... other results]
```

The above search result indicates that one expected search directory for
`linux/i2c.h` is `common/include/uapi`.

**NOTE**: There might be multiple matches. However, usually you only want to
include a specific one.

### Step 1: Check all of the include directories of the DDK module

There are multiple ways to do this. You may look at the generated `Kbuild` file.

Example: If you are compiling
`//common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_sync`, you may
look at:

```shell
$ grep -rn 'goldfish_sync' bazel-bin/common-modules/virtual-device/
[...]
bazel-bin/common-modules/virtual-device/goldfish_drivers/goldfish_sync_makefiles/makefiles/goldfish_drivers/Kbuild:2:obj-m += goldfish_sync.o
[...]

$ grep 'ccflags-y' bazel-bin/common-modules/virtual-device/x86_64/goldfish_drivers/goldfish_sync_makefiles/makefiles/goldfish_drivers/Kbuild
ccflags-y += '-I$(srctree)/$(src)/../../../common/include/uapi'
[... other ccflags-y]
```

The expression `$(srctree)/$(src)` evaluates to
`<package>/<dirname of output module>`.

* Package is `common-modules/virtual-device`.
* Output module is the `out` attribute of the
  `ddk_module` target, which defaults to `<target name>.ko`. In this case, it
  is `goldfish_drivers/goldfish_sync.ko`.

Hence `$(srctree)/$(src)`
is` common-modules/virtual-device/goldfish_drivers` in this case.

Hence, the above include directory points to

```text
<repository_root>/common-modules/virtual-device/goldfish_drivers/../../../common/include/uapi
```

which is just

```text
<repository_root>/common/include/uapi
```

Check if the expected search directories of the missing header found in the
previous step is in these `-I` options.

Another way to determine is to use the `--debug_annotate_scripts` option.
Example:

```shell
$ tools/bazel build \
  //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_sync \
  --debug_annotate_scripts > /tmp/out.log 2>&1
$ grep 'goldfish_sync.o' /tmp/out.log
[clang command]
[... other lines]
```

Examine the command and look for `-I` options, and compare it with the expected
search directories found in step 1.

### Step 3: Look for or define the appropriate target with the headers

See [instructions](#find-ddk-headers) to look for a `ddk_headers` target or
`filegroup` target under the package with the requested header, or look for
[`exports_files` declarations](https://bazel.build/reference/be/functions#exports_files)
manually.

If there's none, [define one](main.md#ddk_headers).

### Step 4: Add to `deps` of the `ddk_module` target

See instructions for [ddk_module](main.md#ddk_module).

## `<built-in>:1:10: fatal error: '<path>/include/linux/compiler-version.h' file not found` {#missing-compiler-version-h}

**NOTE**: This error is about `include/linux/compiler-version.h` and
`include/linux/kconfig.h`.

If you see the following error:

```text
<built-in>:1:10: fatal error: '<path>/include/linux/compiler-version.h' file not found
#include "<path>/include/linux/compiler-version.h"
         ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
1 error generated.
make[3]: *** [<path>/scripts/Makefile.build:286: <module>.o] Error 1
```

The reason is that a module implicitly includes this header (and
`include/linux/kconfig.h`) from the kernel source tree. This is usually listed
in `LINUXINCLUDE` in the `${KERNEL_DIR}`.

To resolve this:

1. Ensure that the `${KERNEL_DIR}` has a `ddk_headers` that exports these
   headers, or a `filegroup` target or
   an [`exports_files` declaration](https://bazel.build/reference/be/functions#exports_files)
   that exports these files.

    * If `${KERNEL_DIR}` points to the Android Common Kernel source tree, there
      should be a `ddk_headers` target named `all_headers`. There may be other
      smaller targets to use. Check the `BUILD.bazel` file under
      the `${KERNEL_DIR}` for the exact declarations.
    * Hint: you may also search all valid `ddk_headers` target with a query
      command; see [instructions](#find-ddk-headers).
    * If `${KERNEL_DIR}` points to a custom kernel source tree that does not
      track the Android Common Kernel source tree, use the `bazel query`
      command above to look for a suitable `ddk_headers` or `filegroup` target,
      or manually look
      for [`exports_files` declarations](https://bazel.build/reference/be/functions#exports_files)
      . If there's none, you can [define one](main.md#ddk_headers). Example:
      ```python
      ddk_headers(
          name = "linuxinclude",
          hdrs = [
              "include/linux/compiler-version.h",
              "include/linux/kconfig.h",
          ],
      )
      ```
2. Add the target found or defined in step 1 to the `deps` attribute of the
   `ddk_modules` target. For example, to add `"//common:all_headers"` to `deps`:
   ```python
   ddk_module(
       name = "foo",
       deps = ["//common:all_headers"],
   )
   ```
   For details, see [ddk_module](main.md#ddk_module).

## Appendix

### Generic instructions for looking for appropriate `ddk_headers` targets to use {#find-ddk-headers}

Example: The following query shows all `ddk_headers` target in `//common` that
includes `common/include/linux/compiler-version.h`, and visible to the 
`ddk_module` named `//common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_sync`

```shell
$ tools/bazel query \
  'visible(//common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_sync, 
           kind(ddk_headers, rdeps(//common:*, //common:include/linux/compiler-version.h)))'
```