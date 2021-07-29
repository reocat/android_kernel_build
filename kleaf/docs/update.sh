#!/usr/bin/env bash

bazel build //build/kleaf:docs
mydir=$(dirname "$0")
rm -f *.md
cp -v ${mydir}/../../../bazel-bin/build/kleaf/*.md ${mydir}
chmod 0644 *.md
