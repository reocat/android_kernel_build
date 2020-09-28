#!/bin/bash

# Usage:
#   build/config.sh <config editor> <make options>*
#
# Example:
#   build/config.sh menuconfig|config|nconfig|... (default to menuconfig)
#
# Runs configuration editor inside kernel/build environment.
#
# The same environment variables are considered in build/build.sh, in addition
# to the following:
#
#   FRAGMENT_CONFIG
#     If set, then the FRAGMENT_CONFIG file (absolute or relative to ROOT_DIR)
#     is updated with the options selected by the config editor.
#
# Note: When editing a FRAGMENT_CONFIG, config.sh is intentionally
#       unintelligent about removing "redundant" configuration options. That is,
#       setting CONFIG_ARM_SMMU=m using config.sh, then unsetting it would
#       result in a fragment config with CONFIG_ARM_SMMU explicitly unset.
#       This behavior is desired since it is unknown whether the base
#       configuration without the fragment would have CONFIG_ARM_SMMU (un)set.
#       If desire is to let the base configuration properly control a CONFIG_
#       option, then remove the line from FRAGMENT_CONFIG

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

set -e
set -a

# Disable hermetic toolchain for ncurses
HERMETIC_TOOLCHAIN=0

source "${ROOT_DIR}/build/_setup_env.sh"

function sort_config() {
  sed -E -e 's/.*(CONFIG_[^ =]+).*/\1 \0/' $1 | sort -k1 | cut -F2-
}
export -f sort_config

function menuconfig() {
  set +x
  local orig_config=$(mktemp)
  local new_config="${OUT_DIR}/.config"
  local changed_config=$(mktemp)
  local new_fragment=$(mktemp)

  trap "rm -f ${orig_config} ${changed_config} ${new_fragment}" EXIT

  if [ -n "${FRAGMENT_CONFIG}" ]; then
    if [[ -f "${ROOT_DIR}/${FRAGMENT_CONFIG}" ]]; then
      FRAGMENT_CONFIG="${ROOT_DIR}/${FRAGMENT_CONFIG}"
    elif [[ "${FRAGMENT_CONFIG}" != /* ]]; then
      echo "FRAGMENT_CONFIG must be an absolute path or relative to ${ROOT_DIR}: ${FRAGMENT_CONFIG}"
      exit 1
    elif [[ ! -f "${FRAGMENT_CONFIG}" ]]; then
      echo "Failed to find FRAGMENT_CONFIG: ${FRAGMENT_CONFIG}"
      exit 1
    fi
  fi

  cp ${OUT_DIR}/.config ${orig_config}
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} ${1:-menuconfig})

  if [ -z "${FRAGMENT_CONFIG}" ]; then
    (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} savedefconfig)
    mv ${OUT_DIR}/defconfig ${DEFCONFIG}
    return
  fi

  ${KERNEL_DIR}/scripts/diffconfig -m ${orig_config} ${new_config} > ${changed_config}
  KCONFIG_CONFIG=${new_fragment} ${ROOT_DIR}/${KERNEL_DIR}/scripts/kconfig/merge_config.sh -m ${FRAGMENT_CONFIG} ${changed_config}
  sort_config ${new_fragment} > ${FRAGMENT_CONFIG}
  set +x


  echo
  echo "Updated ${FRAGMENT_CONFIG}"
  echo
}
export -f menuconfig

# let all the POST_DEFCONFIG_CMDS run since they may clean up loose files, then exit
append_cmd POST_DEFCONFIG_CMDS "exit"
# menuconfig should go first. If POST_DEFCONFIG_CMDS modifies the .config, then we probably don't
# want those changes to end up in the resulting saved defconfig
POST_DEFCONFIG_CMDS="menuconfig $* && ${POST_DEFCONFIG_CMDS}"

${ROOT_DIR}/build/build.sh

set +e
set +a
