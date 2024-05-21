#!/bin/bash -e

build_artifacts="$1"
abi_report=$(cat "${build_artifacts}/abi.report.short")

if [ -n "${abi_report}" ]; then
    echo "ERROR: ABI DIFFERENCES HAVE BEEN DETECTED!" >&2
    echo "ERROR: ${abi_report}" >&2
    exit 1
fi
