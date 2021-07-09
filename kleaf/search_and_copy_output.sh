#!/bin/bash

# search_and_copy_output.sh <module_name> <output_rel_path> <srcdir> <dstdir>
#   Searches <output_rel_path> under <srcdir>, and copy it to
#   <dstdir>/<output_rel_path>
#   There must be exactly one match; otherwise error.

if [[ $# != 4 ]]; then
  echo "Usage: search_and_copy_output.sh <module_name> <output_file_name> <srcdir> <dstdir>"
  exit 1
fi

module_name=$1
output_rel_path=$2
srcdir=$3
dstdir=$4

found=$(find ${srcdir} -wholename '*/'${output_rel_path})
if [[ "${found}" == "" ]]; then
  echo "${module_name}: No files matches \"${output_rel_path}\", expected 1."
  exit 1
fi
num_found=$(echo "${found}" | wc -l)
if [[ "${num_found}" != "1" ]]; then
  echo "${module_name}: More than 1 files matches \"${output_rel_path}\", expected 1:"
  for found_file in ${found}; do
    echo "  ${found_file}"
  done
  exit 1
fi

if [[ ${output_rel_path} != $(basename ${output_rel_path}) ]]; then
  echo "*****" cp ${found} "${dstdir}/$(basename ${output_rel_path})"
  cp ${found} "${dstdir}/$(basename ${output_rel_path})"
fi
echo "******" mv ${found} ${dstdir}/${output_rel_path}
mv ${found} ${dstdir}/${output_rel_path}

num_found=
found=
dstdir=
srcdir=
output_rel_path=
module_name=

