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

# Usage:
#   build/build_initramfs
#
# The following environment variables are considered during execution:
#
#   MODULES_LIST
#      File with a list of module names. Each line contains 1 module
#      name, e.g. arm-smmu.ko.
#
#   ACK_KERNEL_IMG
#     Path to Android Common Kernel Image.gz
#
#   BUILD_CONFIG
#     Build config file to initialize the build environment from. The location
#     is to be defined relative to the repo root directory.
#     Defaults to 'build.config'.
#
#   OUT_DIR
#     Base output directory for the kernel build.
#     Defaults to <REPO_ROOT>/out/<BRANCH>.
#
#   DIST_DIR
#     Base output directory for the kernel distribution.
#     Defaults to <OUT_DIR>/dist
#
#   For building the boot and vendor_boot images you need to define,
#     - MKBOOTIMG_PATH=<path to the mkbootimg.py script which builds boot.img>
#       (defaults to tools/mkbootimg/mkbootimg.py)
#     - GKI_RAMDISK_PREBUILT_BINARY=<Name of the GKI ramdisk prebuilt which includes
#       the generic ramdisk components like init and the non-device-specific rc files>
#     - VENDOR_RAMDISK_BINARY=<Name of the vendor ramdisk binary which includes the
#       device-specific components of ramdisk like the fstab file and the
#       device-specific rc files.>
#     - KERNEL_BINARY=<name of kernel binary, eg. Image.lz4, Image.gz etc>
#     - BOOT_IMAGE_HEADER_VERSION=<version of the boot image header>
#       (defaults to 3)
#     - KERNEL_CMDLINE=<string of kernel parameters for boot>
#     - KERNEL_VENDOR_CMDLINE=<string of kernel parameters for vendor_boot>
#     - VENDOR_FSTAB=<Path to the vendor fstab to be included in the vendor
#       ramdisk>
#     - BOOT_IMAGE_HEADER_VERSION=3, only header version 3 is supported
#     - BASE_ADDRESS=<base address to load the kernel at>
#     - PAGE_SIZE=<flash page size>
#     - GKI_BOOT_ONLY=<0/1>, set to 1 if you only want to package the
#       boot-gki.img

export ROOT_DIR=$(readlink -f $(dirname $0)/..)
source "${ROOT_DIR}/build/_setup_env.sh"

if [ "${BOOT_IMAGE_HEADER_VERSION}" -ne "3" ]; then
	echo "This script only supports header version 3. Please define BOOT_IMAGE_HEADER_VERSION=3"
	exit 1
fi

export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export INITRAMFS_STAGING_DIR=${MODULES_STAGING_DIR}/initramfs_staging

echo "========================================================"
echo " Creating initramfs"
set -x
rm -rf ${INITRAMFS_STAGING_DIR}
# Depmod requires a version number; use 0.0 instead of determining the
# actual kernel version since it is not necessary and will be removed for
# the final initramfs image.
mkdir -p ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/kernel/
mkdir -p ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/extra/

(
  cd ${MIN_MODULES_PATH:-"."}
  cp -r ${MIN_MODULES_PATH:-${MODULES_STAGING_DIR}/lib/modules/*}/kernel/* ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/kernel/
  cp -r ${MIN_MODULES_PATH:-${MODULES_STAGING_DIR}/lib/modules/*}/extra/*  ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/extra/
  find . -type f -name "*.ko" | cut -c3- > ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.load
)

# Re-run depmod to detect any dependencies between in-kernel and external
# modules. Then, create modules.load based on all the modules compiled.
(
  set +x
  set +e # disable exiting of error so we can add extra comments
  cd ${INITRAMFS_STAGING_DIR}
  DEPMOD_OUTPUT=$(depmod -e -F ${DIST_DIR}/System.map -b . 0.0 2>&1)
  if [[ "$?" -ne 0 ]]; then
    echo "$DEPMOD_OUTPUT"
    exit 1;
  fi
  echo "$DEPMOD_OUTPUT"
  if [[ -n $(echo $DEPMOD_OUTPUT | grep "needs unknown symbol") ]]; then
    echo "ERROR: out-of-tree kernel module(s) need unknown symbol(s)"
    #exit 1
  fi
  set -e
  set -x
)
cp ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.load ${DIST_DIR}/modules.load
echo "${MODULES_OPTIONS}" > ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.options
mv ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/* ${INITRAMFS_STAGING_DIR}/lib/modules/.
rmdir ${INITRAMFS_STAGING_DIR}/lib/modules/0.0

mkdir -p ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk
if [ -f "${VENDOR_FSTAB}" ]; then
	cp ${VENDOR_FSTAB} ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk/.
fi

(cd ${INITRAMFS_STAGING_DIR} && find . | cpio -H newc -o > ${MODULES_STAGING_DIR}/initramfs.cpio)
gzip -fc ${MODULES_STAGING_DIR}/initramfs.cpio > ${MODULES_STAGING_DIR}/initramfs.cpio.gz
mv ${MODULES_STAGING_DIR}/initramfs.cpio.gz ${DIST_DIR}/initramfs.img

set -x
MKBOOTIMG_RAMDISKS=()
for ramdisk in ${VENDOR_RAMDISK_BINARY} \
               "${MODULES_STAGING_DIR}/initramfs.cpio"; do
        if [ -f "${DIST_DIR}/${ramdisk}" ]; then
                MKBOOTIMG_RAMDISKS+=("${DIST_DIR}/${ramdisk}")
        else
                if [ -f "${ramdisk}" ]; then
                        MKBOOTIMG_RAMDISKS+=("${ramdisk}")
                fi
        fi
done
set +e # disable exiting of error so gzip -t can be handled properly
for ((i=0; i<"${#MKBOOTIMG_RAMDISKS[@]}"; i++)); do
        TEST_GZIP=$(gzip -t "${MKBOOTIMG_RAMDISKS[$i]}" 2>&1 > /dev/null)
        if [ "$?" -eq 0 ]; then
                CPIO_NAME=$(echo "${MKBOOTIMG_RAMDISKS[$i]}" | sed -e 's/\(.\+\)\.[a-z]\+$/\1.cpio/')
                gzip -cd "${MKBOOTIMG_RAMDISKS[$i]}" > ${CPIO_NAME}
                MKBOOTIMG_RAMDISKS[$i]=${CPIO_NAME}
        fi
done
set -e # re-enable exiting on errors
if [ "${#MKBOOTIMG_RAMDISKS[@]}" -gt 0 ]; then
        cat ${MKBOOTIMG_RAMDISKS[*]} | gzip - > ${DIST_DIR}/ramdisk.gz
else
        echo "No ramdisk found. Please provide a GKI and/or a vendor ramdisk."
        exit 1
fi
set -x

MKBOOTIMG_BASE_ADDR=
MKBOOTIMG_PAGE_SIZE=
MKBOOTIMG_BOOT_CMDLINE=
if [ -n  "${BASE_ADDRESS}" ]; then
	MKBOOTIMG_BASE_ADDR="--base ${BASE_ADDRESS}"
fi
if [ -n  "${PAGE_SIZE}" ]; then
	MKBOOTIMG_PAGE_SIZE="--pagesize ${PAGE_SIZE}"
fi
if [ -n "${KERNEL_CMDLINE}" ]; then
	MKBOOTIMG_BOOT_CMDLINE="--cmdline \"${KERNEL_CMDLINE}\""
fi
if [ -n "${GKI_BOOT_ONLY}" ]; then
	GKI_BOOT_ONLY=0
fi

VENDOR_BOOT_ARGS=
MKBOOTIMG_BOOT_RAMDISK="--ramdisk ${DIST_DIR}/ramdisk.gz"
MKBOOTIMG_VENDOR_CMDLINE=
if [ -n "${KERNEL_VENDOR_CMDLINE}" ]; then
	MKBOOTIMG_VENDOR_CMDLINE="--vendor_cmdline \"${KERNEL_VENDOR_CMDLINE}\""
fi

if [ -z "${MKBOOTIMG_PATH}" ]; then
	MKBOOTIMG_PATH="tools/mkbootimg/mkbootimg.py"
fi
if [ -f "${GKI_RAMDISK_PREBUILT_BINARY}" ]; then
	MKBOOTIMG_BOOT_RAMDISK="--ramdisk ${GKI_RAMDISK_PREBUILT_BINARY}"
fi

VENDOR_BOOT_ARGS="--vendor_boot ${DIST_DIR}/${VENDOR_BOOT_IMG:-vendor_boot.img} \
	--vendor_ramdisk ${DIST_DIR}/ramdisk.gz ${MKBOOTIMG_VENDOR_CMDLINE}"

if [ "${GKI_BOOT_ONLY}" -eq "0" ]; then
	# (b/141990457) Investigate parenthesis issue with MKBOOTIMG_BOOT_CMDLINE when
	# executed outside of this "bash -c".
	(set -x; bash -c "python $MKBOOTIMG_PATH --kernel ${DIST_DIR}/$KERNEL_BINARY \
		${MKBOOTIMG_BOOT_RAMDISK} \
		--dtb ${DIST_DIR}/dtb.img --header_version $BOOT_IMAGE_HEADER_VERSION \
		${MKBOOTIMG_BASE_ADDR} ${MKBOOTIMG_PAGE_SIZE} ${MKBOOTIMG_BOOT_CMDLINE} \
		-o ${DIST_DIR}/${BOOT_IMG:-boot.img} ${VENDOR_BOOT_ARGS}"
	)
fi

if [ -n "${ACK_KERNEL_IMG}" ]; then
(set -x; bash -c "python $MKBOOTIMG_PATH --kernel ${ACK_KERNEL_IMG} \
	${MKBOOTIMG_BOOT_RAMDISK} \
	--header_version $BOOT_IMAGE_HEADER_VERSION \
	${MKBOOTIMG_BASE_ADDR} ${MKBOOTIMG_PAGE_SIZE} ${MKBOOTIMG_BOOT_CMDLINE} \
	-o ${DIST_DIR}/${GKI_BOOT_IMG:-boot-gki.img}"
)
fi

set +x
