#!/bin/bash -e
# Copyright (C) 2021 The Android Open Source Project
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

# Go into .source_date_epoch_dir, then execute scripts/setlocalversion --save-scmversion

# This script is located at ${ROOT_DIR}/build/kleaf/save_scmversion.sh.
ROOT_DIR=$(dirname $(dirname $(dirname $(readlink -f $0 ) ) ) )
SCMVERSION_DIR="${ROOT_DIR}/generated/bazel"

if [[ ! -x "${ROOT_DIR}/.source_date_epoch_dir/scripts/setlocalversion" ]]; then
  exit 0
fi

mkdir -p ${SCMVERSION_DIR}
cd "${ROOT_DIR}/.source_date_epoch_dir"
scripts/setlocalversion --save-scmversion
if [[ ! -f ${SCMVERSION_DIR}/scmversion ]] ||
   ( ! diff .scmversion ${SCMVERSION_DIR}/scmversion > /dev/null ); then
  mv .scmversion ${SCMVERSION_DIR}/scmversion
fi

cat > ${SCMVERSION_DIR}/BUILD.bazel <<EOF
# This file is autogenerated by save_scmversion.sh
filegroup(
  name = "scmversion_filegroup",
  srcs = glob(["scmversion"]),
  visibility = ["//visibility:public"],
)
EOF
