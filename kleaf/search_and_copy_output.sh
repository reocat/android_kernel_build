#!/bin/bash

# search_and_copy_output.sh <module_name> <output_file_name> <srcdir> <dstdir>
#   Searches <output_file_name> under <srcdir>, and copy it to
#   <dstdir>/<output_file_name>
#   There must be exactly one match; otherwise error.

if [[ $# != 4 ]]; then
  echo "Usage: search_and_copy_output.sh <module_name> <output_file_name> <srcdir> <dstdir>"
  exit 1
fi

module_name=$1
output_file_name=$2
srcdir=$3
dstdir=$4

found=$(find "${srcdir}" -name "${output_file_name}")
if [[ "${found}" == "" ]]; then
  echo "${module_name}: No files matches \"${output_file_name}\", expected 1."
  exit 1
fi
num_found=$(echo "${found}" | wc -l)
if [[ "${num_found}" != "1" ]]; then
  echo "${module_name}: More than 1 files matches \"${output_file_name}\", expected 1:"
  for found_file in ${found}; do
    echo "  ${found_file}"
  done
  exit 1
fi

if [[ ${output_file_name} != $(basename ${output_file_name}) ]]; then
  cp ${found} "${dstdir}/$(basename ${output_file_name})"
fi
mv ${found} ${dstdir}/${output_file_name}


