#!/bin/sh
# SPDX-License-Identifier: GPL-2.0

export MIXED_BUILD=1

GKI_BUILD_CONFIG=${GKI_BUILD_CONFIG:-common/build.config.gki.aarch64}

# capture the device branch from the provided BUILD_CONFIG
DEVICE_BRANCH=$(
  source build/_setup_env.sh >/dev/null
  echo $BRANCH
)

BASE_OUT=${OUT_DIR:-out}/mixed/$DEVICE_BRANCH/
export OUT_DIR

# share a common DIST_DIR
export DIST_DIR=${DIST_DIR:-${BASE_OUT}/dist/}

# Now build the GKI kernel
OUT_DIR=${BASE_OUT}/gki-kernel/
SKIP_CP_KERNEL_HDR=1 BUILD_CONFIG=$GKI_BUILD_CONFIG build/build.sh "$@"
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "ERROR: Failed to compile the GKI kernel. (ret=$error_code)" >&2
  exit $error_code
fi

# build the device Kernel using the default/provided BUILD_CONFIG
OUT_DIR=${BASE_OUT}/device-kernel/
build/build.sh "$@"

