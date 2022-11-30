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
"""
Rules for a runnable that builds a boot image at execution phase.
"""

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    ":utils.bzl",
    "utils",
)

def _boot_image_builder_impl(ctx):
    exec = ctx.actions.declare_file(ctx.attr.name + ".sh")

    default_ramdisk = None
    default_ramdisk_files = ctx.files.default_ramdisk
    if default_ramdisk_files:
        if len(ctx.files.default_ramdisk) != 1:
            fail("{}: default_ramdisk {} must contain at most one file".format(
                ctx.label,
                ctx.attr.default_ramdisk.label,
            ))
        default_ramdisk = default_ramdisk_files[0]

    script = ctx.attr._hermetic_tools[HermeticToolsInfo].run_setup

    script += """
        source {build_utils_sh}

        GKI_RAMDISK_PREBUILT_BINARY=$(realpath {default_ramdisk})

        while [[ $# -gt 0 ]]; do
            case $1 in
                --ramdisk=*)
                    GKI_RAMDISK_PREBUILT_BINARY="${{1#*=}}"
                    shift
                    ;;
                --ramdisk)
                    GKI_RAMDISK_PREBUILT_BINARY="$2"
                    shift
                    shift
                    ;;
                --out=*)
                    KLEAF_OUTPUT_BOOT_IMG="${{1#*=}}"
                    shift
                    ;;
                --out)
                    KLEAF_OUTPUT_BOOT_IMG="$2"
                    shift
                    ;;
                *)
                    echo "Unknown arg $1" >&2
                    exit 1
            esac
        done

        if [[ -z "${{GKI_RAMDISK_PREBUILT_BINARY}}" ]]; then
            echo "Please provide a --ramdisk argument." >&2
            exit 1
        fi

        # Arguments must be absolute because `bazel run` executes the script
        # under execroot, not current working directory.
        if [[ "${{GKI_RAMDISK_PREBUILT_BINARY}}" != /* ]]; then
            echo "--ramdisk must be absolute." >&2
            exit 1
        fi

        if [[ -z "${{KLEAF_OUTPUT_BOOT_IMG}}" ]]; then
            KLEAF_OUTPUT_BOOT_IMG="${{BUILD_WORKSPACE_DIRECTORY}}/out/tmp/boot.img"
        fi

        if [[ "${{KLEAF_OUTPUT_BOOT_IMG}}" != /* ]]; then
            echo "--out must be absolute." >&2
            exit 1
        fi

        # Use a fake DIST_DIR so we can set KERNEL_BINARY directly
        DIST_DIR=.
        KERNEL_BINARY={kernel_image}
        MKBOOTIMG_STAGING_DIR=.

        MKBOOTIMG_PATH={mkbootimg}
        BUILD_BOOT_IMG=1
        SKIP_VENDOR_BOOT=1

        build_boot_images

        mkdir -p $(dirname ${{KLEAF_OUTPUT_BOOT_IMG}})
        cp -p ${{DIST_DIR}}/boot.img ${{KLEAF_OUTPUT_BOOT_IMG}}
        echo "boot image copied to ${{KLEAF_OUTPUT_BOOT_IMG}}"
    """.format(
        build_utils_sh = ctx.file._build_utils_sh.short_path,
        kernel_image = ctx.file.kernel_image.short_path,
        default_ramdisk = default_ramdisk.short_path if default_ramdisk else "",
        mkbootimg = ctx.file._mkbootimg.short_path,
    )

    ctx.actions.write(
        output = exec,
        content = script,
        is_executable = True,
    )

    runfiles = [
        ctx.file._build_utils_sh,
        ctx.file.kernel_image,
        ctx.file._mkbootimg,
    ] + ctx.files.default_ramdisk
    runfiles += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    return DefaultInfo(
        executable = exec,
        runfiles = ctx.runfiles(files = runfiles),
    )

boot_image_builder = rule(
    implementation = _boot_image_builder_impl,
    doc = """A runnable target that builds a boot image when it is executed.""",
    attrs = {
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils.sh"),
        ),
        "_mkbootimg": attr.label(
            allow_single_file = True,
            default = "//tools/mkbootimg:mkbootimg.py",
        ),
        "kernel_image": attr.label(allow_single_file = True),
        "default_ramdisk": attr.label(allow_files = True),
    },
    executable = True,
)
