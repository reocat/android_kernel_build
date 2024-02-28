<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Module extension that instantiates key_value_repo.

<a id="kernel_toolchain_ext"></a>

## kernel_toolchain_ext

<pre>
kernel_toolchain_ext = use_extension("@kleaf//build/kernel/kleaf:kernel_toolchain_ext.bzl", "kernel_toolchain_ext")
kernel_toolchain_ext.install(<a href="#kernel_toolchain_ext.install-toolchain_constants">toolchain_constants</a>)
</pre>

Declares an extension named `kernel_toolchain_info` that contains toolchain information.


**TAG CLASSES**

<a id="kernel_toolchain_ext.install"></a>

### install

Declares a potential location that contains toolchain information.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_toolchain_ext.install-toolchain_constants"></a>toolchain_constants |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


