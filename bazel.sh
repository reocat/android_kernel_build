#!/bin/bash -e

ROOT_DIR=$(dirname $(dirname $(readlink -f $0 ) ) )

echo $ROOT_DIR

BAZEL_PATH="${ROOT_DIR}/prebuilts/bazel/linux-x86_64/bazel"
BAZELRC_NAME="common.bazelrc"
BAZEL_JDK_PATH="${ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86"

ABSOLUTE_OUT_DIR="${ROOT_DIR}/out"

"${BAZEL_PATH}" \
  --server_javabase="${BAZEL_JDK_PATH}" \
  --output_user_root="${ABSOLUTE_OUT_DIR}/bazel/output_user_root" \
  --host_jvm_args=-Djava.io.tmpdir="${ABSOLUTE_OUT_DIR}/bazel/javatmp" \
  --bazelrc="${ROOT_DIR}/build/${BAZELRC_NAME}" \
  "$@"

