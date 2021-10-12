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

# Determine scmversion and print it.
# - If KLEAF_SCMVERSION is set, print it
# - Otherwise, go into .source_date_epoch_dir, then execute
#     scripts/setlocalversion --save-scmversion
#   and print the .scmversion file

# Use pre-set values from the environement if it is already set.
if [ ! -z "${KLEAF_SCMVERSION}" ]; then
  echo ${KLEAF_SCMVERSION}
  exit 0
fi

# This script is located at ${ROOT_DIR}/build/kleaf/scmversion.sh.
ROOT_DIR=$(dirname $(dirname $(dirname $(readlink -f $0 ) ) ) )

# If there are any pre-existing .scmversion file, use it, and do not delete it.
if [[ -f ${ROOT_DIR}/.source_date_epoch_dir/.scmversion ]]; then
  cat ${ROOT_DIR}/.source_date_epoch_dir/.scmversion
  exit 0
fi

# If setlocalversion script does not exist, leave KLEAF_SCMVERSION empty.
if [[ ! -x "${ROOT_DIR}/.source_date_epoch_dir/scripts/setlocalversion" ]]; then
  exit 0
fi

cd "${ROOT_DIR}/.source_date_epoch_dir"
scripts/setlocalversion --save-scmversion
cat .scmversion
rm -f .scmversion
