#!/bin/bash -e

function gettop
{
    local TOPFILE=build/kleaf/bazel.sh
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ] ; then
        # The following circumlocution ensures we remove symlinks from TOP.
        (cd "$TOP"; PWD= /bin/pwd)
    else
        if [ -f $TOPFILE ] ; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            local HERE=$PWD
            local T=
            while [ \( ! \( -f $TOPFILE \) \) -a \( "$PWD" != "/" \) ]; do
                \cd ..
                T=`PWD= /bin/pwd -P`
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}

ROOT_DIR=$(gettop)

echo Building in $ROOT_DIR ...

BAZEL_PATH="${ROOT_DIR}/prebuilts/bazel/linux-x86_64/bazel"
BAZEL_JDK_PATH="${ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86"
BAZELRC_NAME="build/kleaf/common.bazelrc"

ABSOLUTE_OUT_DIR="${ROOT_DIR}/out"

"${BAZEL_PATH}" \
  --server_javabase="${BAZEL_JDK_PATH}" \
  --output_user_root="${ABSOLUTE_OUT_DIR}/bazel/output_user_root" \
  --host_jvm_args=-Djava.io.tmpdir="${ABSOLUTE_OUT_DIR}/bazel/javatmp" \
  --bazelrc="${ROOT_DIR}/${BAZELRC_NAME}" \
  "$@"

