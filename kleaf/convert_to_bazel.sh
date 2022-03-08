#!/bin/bash

ROOT_DIR=$($(dirname $(dirname $(readlink -m "$0")))/gettop.sh)

(

cd $ROOT_DIR

# Same as _setup_env.sh. In theory we can also source _setup_env.sh, but to
# reduce overhead, just use this simple logic directly.
BUILD_CONFIG=${BUILD_CONFIG:-build.config}

# Assume that the build config is directly under a package
package_path=$(
    cur_path=$(dirname $BUILD_CONFIG)
    while [[ $cur_path != "." ]] && [[ ! -f $cur_path/BUILD.bazel ]] && [[ ! -f $cur_path/BUILD ]]; do
        cur_path=$(dirname $cur_path)
    done
    echo $cur_path
)
if [[ $package_path == "." ]]; then
    echo "Unable to determine package of build.config" >&2
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
    kind(_kernel_build, \$configs_rdeps)
EOF
)

bazel query "$script" 2>/dev/null

) # ~ popd
