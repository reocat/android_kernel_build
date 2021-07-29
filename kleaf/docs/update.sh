#!/usr/bin/env bash

bazel build //build/kleaf:docs
mydir=$(dirname "$0")
cp -v ${mydir}/../../../bazel-bin/build/kleaf/*.md .
