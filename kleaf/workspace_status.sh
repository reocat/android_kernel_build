#!/bin/bash -e

WORKING_DIR=build/kernel/kleaf/workspace_status_dir
KERNEL_DIR=$(readlink -f .source_date_epoch_dir)

if [[ ! -d $KERNEL_DIR ]]; then
  exit
fi

STABLE_SCMVERSION=$(cd $WORKING_DIR && $KERNEL_DIR/scripts/setlocalversion $KERNEL_DIR)
echo STABLE_SCMVERSION $STABLE_SCMVERSION
