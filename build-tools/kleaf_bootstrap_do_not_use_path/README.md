# Bootstrapping PATH

This directory is prepended to PATH in order to let Bazel prefer using
this path at bootstrapping time. This includes:

- Bootstrapping scripts that are executed before any action
- External rules that are not under our control.

Care must be taken when adding additional tools to this list.

Regular actions should use hermetic toolchain whenever possible.

## cp

Used by `copy_file` rule in `bazel-skylib`.

## uname

Needed by `rules_python` during toolchain resolution.

## python3

The host Python is needed to run any Python binaries. See
https://github.com/bazelbuild/bazel/issues/19355 .
