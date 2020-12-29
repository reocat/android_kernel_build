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

function ack_build_kernel() {
  echo "========================================================"
  echo " Building kernel"

  set -x
  (cd ${OUT_DIR} && make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} ${MAKE_GOALS})
  set +x
}
export -f ack_build_kernel

# Install in-kernel kernel modules
# $1 module install path
# $2 strip flag
#
function ack_mod_install() {
  local install_mod_path=$1
  local strip_flag=$2
  echo "========================================================"
  echo " Installing kernel modules into staging directory"

  (cd ${OUT_DIR} &&  \
   make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${strip_flag} \
        INSTALL_MOD_PATH=${install_mod_path} ${MAKE_ARGS} modules_install)
}
export -f ack_mod_install

# Install external kernel modules
# $1 module install path
# $2 strip flag
# ... list of directories of the external kernel modules
#
function ack_mod_install_ext() {
  local install_mod_path=$1
  local strip_flag=$2
  shift
  shift
  local ext_modules=$@
  echo "========================================================"
  echo " Building external modules and installing them into staging directory"
  for ext_mod in ${ext_modules}; do
    # The path that we pass in via the variable M needs to be a relative path
    # relative to the kernel source directory. The source files will then be
    # looked for in ${KERNEL_DIR}/${ext_mod_rel} and the object files (i.e. .o
    # and .ko) files will be stored in ${OUT_DIR}/${ext_mod_rel}. If we
    # instead set M to an absolute path, then object (i.e. .o and .ko) files
    # are stored in the module source directory which is not what we want.
    local ext_mod_rel=$(rel_path ${ROOT_DIR}/${ext_mod} ${KERNEL_DIR})
    # The output directory must exist before we invoke make. Otherwise, the
    # build system behaves horribly wrong.
    mkdir -p ${OUT_DIR}/${ext_mod_rel}
    set -x
    make -C ${ext_mod} M=${ext_mod_rel} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                       O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS}
    make -C ${ext_mod} M=${ext_mod_rel} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                       O=${OUT_DIR} "${TOOL_ARGS[@]}" ${strip_flag}           \
                       INSTALL_MOD_PATH=${install_mod_path}                   \
                       ${MAKE_ARGS} modules_install
    set +x
  done
}
export -f ack_mod_install_ext

# $1 destination directory
# $2 modules staging directory
#
function ack_mod_dist() {
  local dist_dir=$1
  local modules_dir=$2
  modules=$(find ${modules_dir} -type f -name "*.ko")
  echo "========================================================"
  echo " Copying modules files"
  for file in ${modules}; do
    echo "  ${file#${modules_dir}/}"
    cp -p ${file} ${dist_dir}
  done
}
export -f ack_mod_dist

function version_greater_than() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

function ack_abi_toolcheck() {
  # ensure that abigail is present in path
  if ! ( hash abidiff 2>/dev/null); then
    echo "ERROR: libabigail is not found in \$PATH at all!"
    echo "Have you run build/abi/bootstrap and followed the instructions?"
    echo "./build/abi/bootstrap may help"
    return 1
  fi

  # ensure we have a "new enough" version of abigail present before continuing
  if ! ( version_greater_than "$(abidiff --version | awk '{print $2}')"  \
                  "1.6.0" ); then
    echo "ERROR: no suitable libabigail (>= 1.6.0) in \$PATH."
    echo "Have you run build/abi/bootstrap and followed the instructions?"
    return 1
  fi

  # For now we require a specific versions of libabigail identified by a commit
  # hash. That is a bit inconvenient, but we do not have another reliable
  # identifier at this time.
  required_abigail_version="1.8.0-$(cat ${ROOT_DIR}/build/abi/bootstrap| grep 'ABIGAIL_VERSION=' | cut -d= -f2)"
  if [[ ! $(abidiff --version) =~ $required_abigail_version ]]; then
    echo "ERROR: required libabigail version is $required_abigail_version"
    echo "Have you run build/abi/bootstrap and followed the instructions?"
    return 1
  fi
}
export -f ack_abi_toolcheck

# $1 symbol_list
#      the symbol list to create
#
# $2 kmi_symbol_list_add_only
#      Set 1 if any symbols in the symbol list that would have been removed are
#      preserved (at the end of the file). This property is intended to prevent
#      unintentional shrinkage of a stable ABI.
#
# $3 full_gki_abi
#      Set 1 then when updating the symbol list, use all defined symbols from
#      vmlinux and GKI modules, instead of the undefined symbols from vendor
#      modules. This property is disabled by default.
#
# $4 kmi_symbol_list_module_grouping
#      Set 1 then the symbol list will group symbols based on the kernel
#      modules that reference the symbol. Otherwise the symbol list will simply
#      be a sorted list of symbols used by all the kernel modules.
#
# $5 gsi_modules_list_file
#      A file that contains list of GSI modules
#
function ack_abi_symbol_extract() {
  local symbol_list=$1
  local kmi_symbol_list_add_only=$2
  local full_gki_abi=$3
  local kmi_symbol_list_module_grouping=$4
  local gsi_modules_list_file=$5

  # Delegate the actual build to build.sh.
  # Suppress possible values of ABI_DEFINITION when invoking build.sh to avoid
  # the generated abi.xml to be copied to <DIST_DIR>/abi.out.
  # Turn on symtypes generation to assist in the diagnosis of CRC differences.
  # Disable KMI trimming as the symbol list may be out of date.
  OUT_DIR_SUFFIX="_abi" \
  TRIM_NONLISTED_KMI= \
  KMI_SYMBOL_LIST_STRICT_MODE= \
  ABI_DEFINITION= \
  KBUILD_SYMTYPES=1 \
    ${ROOT_DIR}/build/build.sh ${MAKE_ARGS}
  echo "========================================================"
  echo " Updating the ABI symbol list to $symbol_list "
  # Exclude GKI modules from non-GKI builds
  if [ -n "${gsi_modules_list_file}" ]; then
    local gki_mod_flag="--gki-modules ${DIST_DIR}/$(basename ${gsi_modules_list_file})"
  fi
  if [ "$kmi_symbol_list_add_only" -eq 1 ]; then
    local add_only_flag="--additions-only"
  fi
  # Specify a full GKI ABI if requested
  if [ "$full_gki_abi" -eq 1 ]; then
    local full_abi_flag="--full-gki-abi"
  fi

  if [ "${kmi_symbol_list_module_grouping}" -eq "0" ]; then
    local skip_module_grouping="--skip-module-grouping"
  fi
  ${ROOT_DIR}/build/abi/extract_symbols          \
      --symbol-list $symbol_list                 \
      ${skip_module_grouping}                    \
      ${add_only_flag}                           \
      ${gki_mod_flag}                            \
      ${full_abi_flag}                           \
      ${DIST_DIR}
}
export -f ack_abi_symbol_extract
