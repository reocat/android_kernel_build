#!/bin/bash -e

abi_reports_path="$1"
abi_report=$(cat "${abi_reports_path}/abi.report.short")

if [ -n "${abi_report}" ]; then
    echo "ERROR: ABI DIFFERENCES HAVE BEEN DETECTED!" >&2
    echo "ERROR: ${abi_report}" >&2
    exit 1
fi
