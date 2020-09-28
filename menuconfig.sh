#!/bin/bash

# Usage:
#   build/menuconfig.sh <config editor> <make options>*
#
# Example:
#   build/menuconfig.sh             (to use menu-based config program)
#   build/menuconfig.sh config      (to use line-oriented config program)
#
# Runs configuration editor inside kernel/build, defaulting to menuconfig.
#
#
# The same environment varaibles are considered in build/build.sh, in addition
# to the following:
#
#   FRAGMENT_CONFIG
#     If set, then the FRAGMENT_CONFIG file (absolute or relative to ROOT_DIR)
#     is updated with the options selected by the config editor.

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

set -e
set -a

SKIP_MRPROPER=1

source "${ROOT_DIR}/build/_setup_env.sh"

function menuconfig() {
  set +x
  local orig_defconfig=$(mktemp)
  local orig_config=$(mktemp)

  if [ -n "${FRAGMENT_CONFIG}" ]; then
    if [[ -f "${ROOT_DIR}/${FRAGMENT_CONFIG}" ]]; then
      FRAGMENT_CONFIG="${ROOT_DIR}/${FRAGMENT_CONFIG}"
    elif [[ "${FRAGMENT_CONFIG}" != /* ]]; then
      echo "FRAGMENT_CONFiG must be an absolute path or relative to ${ROOT_DIR}: ${FRAGMENT_CONFIG}"
      exit 1
    elif [[ ! -f "${FRAGMENT_CONFIG}" ]]; then
      echo "Failed to find modules_list_file: ${FRAGMENT_CONFIG}"
      exit 1
    fi
  fi

  cp ${OUT_DIR}/.config ${orig_config}
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} savedefconfig)
  mv ${OUT_DIR}/defconfig ${orig_defconfig}

  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} ${1:-menuconfig})
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} savedefconfig)
  mv ${OUT_DIR}/defconfig ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}

  if [ -z "${FRAGMENT_CONFIG}" ]; then
    rm "${orig_config}" "${orig_defconfig}"
    exit
  fi

  local new_defconfig="${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}"
  local new_config="${OUT_DIR}/.config"

  # CONFIGs to be added
  # 'defconfig' file should have been generated.
  # Diff this with the 'defconfig_base' from the previous step and extract only the lines that were added
  # Finally, remove the "+" from the beginning of the lines and append it to the FRAGMENT
  diff -u ${orig_defconfig} ${new_defconfig} | grep "^+CONFIG_" | sed 's/^.//' >> ${FRAGMENT_CONFIG}

  # CONFIGs to be removed
  configs_to_remove=`diff -u ${orig_defconfig} ${new_defconfig} | grep "^-CONFIG_" | sed 's/^.//'`
  for config_del in $configs_to_remove; do
    sed -i "/$config_del/d" ${FRAGMENT_CONFIG}
  done

  # CONFIGs that are unset in base defconfig (# CONFIG_X is not set), but enabled in fragments,
  # the diff is shown as: -# CONFIG_X is not set. Hence, explicitly set them in the config fragments.
  configs_to_set=`diff -u ${orig_defconfig} ${new_defconfig} | grep "^-# CONFIG_" | awk '{print $2}'`
  for config_to_set in $configs_to_set; do
    # The CONFIG could be set as 'm' in the previous steps. Ignore setting them to 'y'
    if ! grep -q "$config_to_set" ${FRAGMENT_CONFIG}; then
      echo $config_to_set=y >> ${FRAGMENT_CONFIG}
    fi
  done

  # CONFIGs that are set in base defconfig (or lower fragment), but wanted it to be disabled in FRAG_CONFIG
  diff -u ${orig_config} ${new_config} | grep "^+# CONFIG_" | sed 's/^.//' >> ${FRAGMENT_CONFIG}

  echo
  echo "Updated ${FRAGMENT_CONFIG}"
  echo

  rm "${orig_config}" "${orig_defconfig}"
  exit
}
export -f menuconfig

POST_DEFCONFIG_CMDS="menuconfig $* && exit 1"

${ROOT_DIR}/build/build.sh

set +e
set +a
