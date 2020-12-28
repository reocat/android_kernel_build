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

# $1 Set 1 if using LLVM
#
function ack_setup_toolchain() {
  local llvm=$1
  echo "========================================================"
  echo " Setting up toolchain"
  # Restore the previously saved CC argument that might have been overridden by
  # the BUILD_CONFIG.
  [ -n "${CC_ARG}" ] && CC="${CC_ARG}"

  # CC=gcc is effectively a fallback to the default gcc including any target
  # triplets. An absolute path (e.g., CC=/usr/bin/gcc) must be specified to use a
  # custom compiler.
  [ "${CC}" == "gcc" ] && unset CC && unset CC_ARG

  TOOL_ARGS=()

  # LLVM=1 implies what is otherwise set below; it is a more concise way of
  # specifying CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy <etc>, for
  # newer kernel versions.
  if [[ "${llvm}" -eq 1 ]]; then
    TOOL_ARGS+=("LLVM=1")
    # Reset a bunch of variables that the kernel's top level Makefile does, just
    # in case someone tries to use these binaries in this script such as in
    # initramfs generation below.
    HOSTCC=clang
    HOSTCXX=clang++
    CC=clang
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    OBJSIZE=llvm-size
    STRIP=llvm-strip
  else
    if [ -n "${HOSTCC}" ]; then
      TOOL_ARGS+=("HOSTCC=${HOSTCC}")
    fi

    if [ -n "${CC}" ]; then
      TOOL_ARGS+=("CC=${CC}")
      if [ -z "${HOSTCC}" ]; then
        TOOL_ARGS+=("HOSTCC=${CC}")
      fi
    fi

    if [ -n "${LD}" ]; then
      TOOL_ARGS+=("LD=${LD}" "HOSTLD=${LD}")
      custom_ld=${LD##*.}
      if [ -n "${custom_ld}" ]; then
        TOOL_ARGS+=("HOSTLDFLAGS=-fuse-ld=${custom_ld}")
      fi
    fi

    if [ -n "${NM}" ]; then
      TOOL_ARGS+=("NM=${NM}")
    fi

    if [ -n "${OBJCOPY}" ]; then
      TOOL_ARGS+=("OBJCOPY=${OBJCOPY}")
    fi
  fi

  if [ -n "${LLVM_IAS}" ]; then
    TOOL_ARGS+=("LLVM_IAS=${LLVM_IAS}")
    # Reset $AS for the same reason that we reset $CC etc above.
    AS=clang
  fi

  if [ -n "${DEPMOD}" ]; then
    TOOL_ARGS+=("DEPMOD=${DEPMOD}")
  fi

  if [ -n "${DTC}" ]; then
    TOOL_ARGS+=("DTC=${DTC}")
  fi

  echo "TOOL_ARGS=${TOOL_ARGS[@]}"
}
export -f ack_setup_toolchain

# $@ TOOL_ARGS
#
function ack_mrproper() {
    echo "========================================================"
    echo " Cleaning up for build"
    set -x
    (cd ${KERNEL_DIR} && make "$@" O=${OUT_DIR} ${MAKE_ARGS} mrproper)
    set +x
}
export -f ack_mrproper

# $1 defconfig
# PRE_DEFCONFIG_CMDS: commands to execute before defconfig
# POST_DEFCONFIG_CMDS:commands to execute after defconfig
#
function ack_config() {
  local defconfig=$1

  if [ -n "${PRE_DEFCONFIG_CMDS}" ]; then
    echo "========================================================"
    echo " Running pre-defconfig command(s):"
    set -x
    eval ${PRE_DEFCONFIG_CMDS}
    set +x
  fi

  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} ${defconfig})
  set +x

  if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
    echo "========================================================"
    echo " Running pre-make command(s):"
    set -x
    eval ${POST_DEFCONFIG_CMDS}
    set +x
  fi
}
export -f ack_config

# $1 abi_symbol_list a file that contains list of KMI symbols
#
function ack_config_trim_kmi() {
  local abi_symbol_list=$1
  echo "========================================================"
  echo " Strip symbols not listed in ${abi_symbol_list}"

  pushd $ROOT_DIR/$KERNEL_DIR
  # Create the raw symbol list
  cat ${abi_symbol_list} | \
          ${ROOT_DIR}/build/abi/flatten_symbol_list > \
          ${OUT_DIR}/abi_symbollist.raw

  # Update the kernel configuration
  ./scripts/config --file ${OUT_DIR}/.config \
          -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
          --set-str UNUSED_KSYMS_WHITELIST ${OUT_DIR}/abi_symbollist.raw
  (cd ${OUT_DIR} && \
          make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} olddefconfig)
  # Make sure the config is applied
  grep CONFIG_UNUSED_KSYMS_WHITELIST ${OUT_DIR}/.config > /dev/null || {
    echo "ERROR: Failed to apply TRIM_NONLISTED_KMI kernel configuration" >&2
    echo "Does your kernel support CONFIG_UNUSED_KSYMS_WHITELIST?" >&2
    return 1
  }
  popd # $ROOT_DIR/$KERNEL_DIR
}
export -f ack_config_trim_kmi
