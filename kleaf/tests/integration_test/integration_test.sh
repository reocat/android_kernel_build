#!/bin/bash

# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Usage:
#   bazel run //build/kernel/kleaf/test/integration_test -- [--config=ants [...]]
#
# Note:
# * Use `bazel run` not `bazel test`
# * Flags to recursive bazel calls must be placed after --

if [[ -z $BUILD_WORKSPACE_DIRECTORY ]]; then
  echo "BUILD_WORKSPACE_DIRECTORY is not set" >&2
  exit 1
fi

export RAW_TEST_RESULT_DIR=$(mktemp -d)
trap "rm -rf $RAW_TEST_RESULT_DIR" EXIT

export XML_OUTPUT_FILE=$RAW_TEST_RESULT_DIR/output.xml
export TEST_STDOUT=$RAW_TEST_RESULT_DIR/stdout.txt
export TEST_STDERR=$RAW_TEST_RESULT_DIR/stderr.txt
export TEST_EXITCODE=$RAW_TEST_RESULT_DIR/exitcode.txt

echo RAW_TEST_RESULT_DIR=$RAW_TEST_RESULT_DIR

cd $BUILD_WORKSPACE_DIRECTORY

( (
  prebuilts/build-tools/path/linux-x86/python3 \
    build/kernel/kleaf/tests/integration_test/integration_test.py "$@";
  echo $? > $TEST_EXITCODE
) | tee $TEST_STDOUT ) 3>&1 1>&2 2>&3 | tee $TEST_STDERR

tools/bazel test \
  "$@" \
  --test_output=all \
  --//build/kernel/kleaf/tests/integration_test:raw_test_result_dir="$RAW_TEST_RESULT_DIR" \
  //build/kernel/kleaf/tests/integration_test:reporter