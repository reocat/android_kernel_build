# Customize Workspace

## Use provided `WORKSPACE` file (recommended)

Usually, the common kernel is checked out to `common/`. In this case, it is
recommended to use `build/kernel/kleaf/bazel.WORKSPACE` as the `WORKSPACE`
file.

To do so, modify the repo manifest to create symlink `WORKSPACE` that points
to `build/kernel/kleaf/bazel.WORKSPACE`.

## Use customized `WORKSPACE` file

If the common kernel is checked out to a path other than `common`, you need to
provide a customized `WORKSPACE` file.

The customized `WORKSPACE` file should look similar to
`build/kernel/kleaf/bazel.WORKSPACE`, except that `define_kleaf_workspace()`
should be called with argument `common_kernel_package` set to the path to the
common kernel source tree.

For example, refer to the following structure in the source tree:

```text
<repo_root>
  |- .repo/manifests/default.xml
  |
  |- aosp/
  |  `- <common kernel source tree>
  |  
  |- build/kernel/kleaf/bazel.WORKSPACE
  |
  |- private/tuna/
  |  |- BUILD.bazel
  |  `- bazel.WORKSPACE
  |
  `- WORKSPACE -> build/kernel/kleaf/bazel.WORKSPACE
```

Sample manifest in `.repo/manifests/default.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="aosp" fetch=".."
            review="https://android-review.googlesource.com/"/>
    <remote name="partner" fetch=".."
            review="https://partner-android-review.googlesource.com/"/>

    <!-- Common kernel is checked out to aosp/ -->
    <project path="aosp" name="kernel/common" remote="aosp"
             revision="android-mainline">
        <!-- links omitted -->
    </project>

    <project path="build/kernel" name="kernel/build" remote="aosp"
             revision="android-mainline">
        <!-- drop the WORKSPACE link -->
        <!-- linkfile src="kleaf/bazel.WORKSPACE" dest="WORKSPACE" / -->
        <!-- other links omitted -->
    </project>

    <!-- device kernel configs & modules -->
    <project path="private/tuna" name="private/tuna" remote="partner"
             revision="tuna-mainline">
        <!-- Create the custom WORKSPACE link -->
        <linkfile src="bazel.WORKSPACE" dest="WORKSPACE"/>
    </project>
    <!-- other projects omitted -->
</manifest>
```

Sample workspace file in `private/tuna/bazel.WORKSPACE`:

```python
# Call with common_kernel_package = path to the common kernel source tree
load("//build/kernel/kleaf:workspace.bzl", "define_kleaf_workspace")
define_kleaf_workspace(common_kernel_package = "aosp")

# Optional epilog for analysis testing.
# https://bazel.build/rules/testing
load("//build/kernel/kleaf:workspace_epilog.bzl",
     "define_kleaf_workspace_epilog")
define_kleaf_workspace_epilog()
```
