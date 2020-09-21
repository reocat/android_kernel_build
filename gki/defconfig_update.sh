#!/bin/bash

# Copyright (C) 2020 The Android Open Source Project
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

# defconfig_update.sh
#
# Uses the scripts/config script in the kernel tree to update the
# gki_defconfig.
#
# Usage:
#  build/gki/defconfig_update.sh <arch> <config commands>
#
# where <arch> is either arm64 or x86, and <config commands> are commands
# for manipulating kernel config options as defined by scripts/config
# in the kernel tree.

set -e

export ROOT_DIR=$(readlink -f $(dirname $0)/../..)

if [[ "$1" == "arm64" ]]; then
	BUILD_CONFIG=common/build.config.gki.aarch64
else
	BUILD_CONFIG=common/build.config.gki.x86_64
fi

source "${ROOT_DIR}/build/_setup_env.sh"

make -C "${ROOT_DIR}/common" O=${OUT_DIR} CC=clang LD=ld.lld gki_defconfig

common/scripts/config --file $OUT_DIR/.config "${@:2}"

make -C "${ROOT_DIR}/common" O=${OUT_DIR} CC=clang LD=ld.lld oldconfig
make -C "${ROOT_DIR}/common" O=${OUT_DIR} CC=clang LD=ld.lld savedefconfig
mv "${OUT_DIR}/defconfig" "${ROOT_DIR}/common/arch/$1/configs/gki_defconfig"
