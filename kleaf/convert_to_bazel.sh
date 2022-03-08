#!/bin/bash

# Copyright (C) 2022 The Android Open Source Project
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

set -e

ROOT_DIR=$($(dirname $(dirname $(readlink -m "$0")))/gettop.sh)

BAZEL=$(which bazel >/dev/null && echo "bazel" || echo "tools/bazel")

targets=$(

    cd $ROOT_DIR

    # Same as _setup_env.sh. In theory we can also source _setup_env.sh, but to
    # reduce overhead, just use this simple logic directly.
    BUILD_CONFIG=${BUILD_CONFIG:-build.config}

    if [[ ! -f $BUILD_CONFIG ]]; then
        echo "ERROR: BUILD_CONFIG does not exist." >&2
        exit 1
    fi

    # Assume that the build config is directly under a package
    package_path=$(
        cur_path=$(dirname $BUILD_CONFIG)
        while [[ $cur_path != "." ]] && [[ ! -f $cur_path/BUILD.bazel ]] && [[ ! -f $cur_path/BUILD ]]; do
            cur_path=$(dirname $cur_path)
        done
        echo $cur_path
    )
    if [[ $package_path == "." ]]; then
        cat >&2 <<EOF
    WARNING: Unable to determine package of build.config. Please migrate to Bazel.
    See
        https://android.googlesource.com/kernel/build/+/refs/heads/master/kleaf/README.md
EOF
        exit 1
    fi
    build_config_base=${BUILD_CONFIG#$package_path/}

    package="//$package_path"
    build_config_label="$package:$build_config_base"

    script=$(cat <<EOF
        let pkg_targets = set($package:*) in
        let build_config_rdeps = attr(build_config, "$build_config_label", \$pkg_targets) in
        let env = kind(_kernel_env, \$build_config_rdeps) in
        let env_rdeps = same_pkg_direct_rdeps(\$env) in
        let configs = kind(_kernel_config, \$env_rdeps) in
        let configs_rdeps = same_pkg_direct_rdeps(\$configs) in
        let kernel_builds = kind(_kernel_build, \$configs_rdeps) in
        let filtered_builds = filter("(?<!_notrim_internal)$", \$kernel_builds) in
        \$filtered_builds
EOF
    )

    $BAZEL query "$script" 2>/dev/null

) # targets

if [[ $? != 0 ]]; then
    exit 1
fi

flags=""

if [[ -n "$LTO" ]]; then
    flags="$flags --lto=$LTO"
fi

# Intentionally not quote $targets so lines becomes tokens
echo $BAZEL "build" $flags $targets
