#!/bin/bash

set -e
#set -x

source $(dirname $0)/_init.sh

#exec llvm-cov-11 gcov "$@"
[ -z "$ANDROID_GCOV_LLVM_BIN" ] && exit 1

#echo "GCOV ARGUMENTS: $@"
exec $ANDROID_GCOV_LLVM_BIN gcov -s="/usr" "$@"
