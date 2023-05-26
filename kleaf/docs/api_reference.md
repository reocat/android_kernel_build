# API Reference and Documentation for all rules

## android-mainline

You may view the documentation for the aforementioned Bazel rules and macros on
Android Continuous Integration:

[https://ci.android.com/builds/latest/branches/aosp\_kernel-kleaf-docs/targets/kleaf\_docs/view/index.html](https://ci.android.com/builds/latest/branches/aosp_kernel-kleaf-docs/targets/kleaf_docs/view/index.html)

The link redirects to the latest documentation in the android-mainline branch.

## Viewing docs locally

For an API reference for other branches, or your local repository, you may build
the documentation and view it locally:

```shell
$ tools/bazel run //build/kernel/kleaf:docs_server
```

**Note**: For this, two repositories need to be *vendored* in the same way they
are done for
[`kleaf-docs` branch](https://android.git.corp.google.com/kernel/manifest/+/refs/heads/kleaf-docs):

1.  Include them in your manifest (Note: this is about ~110Mb disk space):
    *   `<project path="prebuilts/bazel/common"
        name="platform/prebuilts/bazel/common" clone-depth="1" />`
1.  Register them as part of the WORKSPACE setup:
    *   `define_kleaf_workspace(include_remote_java_tools_repo = True)`
    *   See
        [kleaf/bazel.kleaf-docs.WORKSPACE](https://android.git.corp.google.com/kernel/build/+/refs/heads/master/kleaf/bazel.kleaf-docs.WORKSPACE)
        for reference.

Sample output:

```text
Serving HTTP on 0.0.0.0 port 8080 (http://0.0.0.0:8080/) ...
```

Then visit `http://0.0.0.0:8080/` in your browser.

**Alternatively**, you may refer to the documentation in the source code of the
Bazel rules in `build/kernel/kleaf/*.bzl`.
