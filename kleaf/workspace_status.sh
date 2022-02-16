#!/bin/bash -e
# Copyright (C) 2022 The Android Open Source Project
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

WORKING_DIR=build/kernel/kleaf/workspace_status_dir
KERNEL_DIR=$(readlink -f .source_date_epoch_dir)

if [[ ! -d $KERNEL_DIR ]]; then
  exit
fi

# Use "git" from the environment.
STABLE_SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C $KERNEL_DIR log -1 --pretty=%ct)}
echo STABLE_SOURCE_DATE_EPOCH $STABLE_SOURCE_DATE_EPOCH

STABLE_SCMVERSION=$(cd $WORKING_DIR && $KERNEL_DIR/scripts/setlocalversion $KERNEL_DIR)
echo STABLE_SCMVERSION $STABLE_SCMVERSION

