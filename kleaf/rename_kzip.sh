#!/bin/bash -uv
#
# Build kzip files (source files for the indexing pipeline) for the given configuration,
# merge them and place the resulting all.kzip into $DIST_DIR.
# It is assumed that the current directory is the top of the source tree.
# The following environment variables affect the result:
#   BUILD_NUMBER          build number, used to generate unique ID (will use UUID if not set)
#   SUPERPROJECT_SHA      superproject sha, used to generate unique id (will use BUILD_NUMBER if not set)
#   SUPERPROJECT_REVISION superproject revision, used for unique id if defined as a sha
#   KZIP_NAME             name of the output file (will use SUPERPROJECT_REVISION|SUPERPROJECT_SHA|BUILD_NUMBER|UUID if not set)
#   DIST_DIR              where the resulting all.kzip will be placed

echo "KZIP_NAME=${KZIP_NAME}"
echo "SUPERPROJECT_REVISION=${SUPERPROJECT_REVISION}"
echo "SUPERPROJECT_SHA=${SUPERPROJECT_SHA}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"

if [[ ${SUPERPROJECT_REVISION:-} =~ [0-9a-f]{40} ]]; then
  : ${KZIP_NAME:=${SUPERPROJECT_REVISION:-}}
fi

: ${KZIP_NAME:=${SUPERPROJECT_SHA:-}}
: ${KZIP_NAME:=${BUILD_NUMBER:-}}
: ${KZIP_NAME:=$(uuidgen)}

echo "Moving ${DIST_DIR}/all.kzip to ${DIST_DIR}/${KZIP_NAME}.kzip"

mv ${DIST_DIR}/all.kzip ${DIST_DIR}/${KZIP_NAME}.kzip
