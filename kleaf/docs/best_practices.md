# Best Practices

This documentation summarizes principles used in Kleaf development..

### Style Guides

* Follow [.bzl style guide](https://bazel.build/rules/bzl-style) for Starlark
  files.
* Follow [BUILD Style Guide](https://bazel.build/build/style-guide) for BUILD
  files.

### Conventions

* For optional arguments in macros, Initialize them with `None` then  assign
 their default value whithin the macro implementation.

* For efficiency reasons, use [depset](https://bazel.build/rules/lib/depset)
  when possible.

