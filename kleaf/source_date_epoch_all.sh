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

# Determine the proper value of SOURCE_DATE_EPOCH, and print it.
# - If already set, print the preset value
# - Otherwise, try to determine from the youngest committer time that can be found across the repos
# - If that fails, fallback to 0
#
# For details about SOURCE_DATE_EPOCH, see
# https://reproducible-builds.org/docs/source-date-epoch/

# This script is located at ${ROOT_DIR}/build/{kernel/,}kleaf/source_date_epoch_all.sh.
# TODO(b/204425264): remove hack once we cut over to build/kernel/ for branches
ROOT_DIR=$(dirname $(dirname $(dirname $(readlink -f $0 ) ) ) )
if [[ ! -f ${ROOT_DIR}/WORKSPACE ]]; then
  ROOT_DIR=$(dirname ${ROOT_DIR})
fi

# Use pre-set values from the environement if it is already set.
if [ ! -z "${SOURCE_DATE_EPOCH}" ]; then
  echo ${SOURCE_DATE_EPOCH}
  exit 0
fi

all_ts=()
for d in $(find ${ROOT_DIR} -name ".git" -type d); do
  all_ts+=($(git -C ${d} log -1 --pretty=%ct))
done

( for ts in "${all_ts[@]}"; do echo ${ts}; done ) | sort -n | tail -n 1
