# Testing Kleaf

Some basic tests can be performed with `bazel test` command. For details of
Bazel testing, please visit

[https://bazel.build/rules/testing](https://bazel.build/rules/testing)

## `kernel_build` rule

For a `kernel_build()` named `foo`, the following targets are created. You
may execute the tests with

```shell
$ bazel test foo_module_test foo_test
```

## `kernel_module` rule

For a `kernel_module()` named `foo`, a target called `foo_test` is created. You
may execute the test with

```shell
$ bazel test foo_test
```
