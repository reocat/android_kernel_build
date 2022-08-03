#!/usr/bin/env python3

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

# A script that converts existing build.config to a skeleton Bazel BUILD rules
# for starters.
#
# Requires buildozer: Install at
#   https://github.com/bazelbuild/buildtools/blob/master/buildozer/README.md
import argparse
import collections
import json
import logging
import os
import subprocess
import sys
import tempfile

BUILD_CONFIG_PREFIX = "build.config."
BUILDOZER_NO_CHANGES_MADE = 3
DEFAULT_KERNEL_BUILD_SRCS = """glob(["**"], exclude=["**/.*", "**/.*/**", "**/BUILD.bazel", "**/*.bzl",])"""


def fail(msg):
    logging.error("%s", msg)
    sys.exit(1)


def order_dict_by_key(d):
    return collections.OrderedDict(sorted(d.items()))


def find_buildozer():
    gopath = os.environ.get("GOPATH", os.path.join(os.environ["HOME"], "go"))
    buildozer = os.path.join(gopath, "bin", "buildozer")
    if not os.path.isfile(buildozer):
        fail("Can't find buildozer. Install with instructions at "
             "https://github.com/bazelbuild/buildtools/blob/master/buildozer/README.md")
    return buildozer


def readlink_if_link(path):
    # if [[ -l $x ]]; then readlink $x; else echo $x; fi
    if os.path.islink(path):
        return os.readlink(path)
    return path


def find_build_config(env):
    # Set by either environment or _setup_env.sh
    if env.get("BUILD_CONFIG"):
        return readlink_if_link(env["BUILD_CONFIG"])
    fail("$BUILD_CONFIG is not set, and top level build.config file is not found.")


def infer_target_name(args, build_config):
    if args.target:
        return args.target
    build_config_base = os.path.basename(build_config)
    if build_config_base.startswith(
            BUILD_CONFIG_PREFIX) and build_config_base != BUILD_CONFIG_PREFIX:
        return build_config_base[len(BUILD_CONFIG_PREFIX):]
    fail("Fail to infer target name. Specify with --target.")


def dict_subtract(a, b):
    a = dict(a)
    for b_key, b_value in b.items():
        if b_key in a and a[b_key] == b_value:
            del a[b_key]
    return a


def ensure_build_file(package):
    if os.path.isabs(package):
        fail(f"$BUILD_CONFIG must be a relative path.")
    if not os.path.exists(os.path.join(package, "BUILD.bazel")) and not os.path.exists(
            os.path.join(package, "BUILD")):
        build_file = os.path.join(package, "BUILD.bazel")
        logging.info(f"Creating {build_file}")
        with open(os.path.join(build_file), "w"):
            pass


def is_ignored_build_config(build_config):
    if build_config in (
            "OUT_DIR",
            "MAKE_GOALS",
            "LD",
            "HERMETIC_TOOLCHAIN",
            "SKIP_MRPROPER",
            "SKIP_DEFCONFIG",
            "SKIP_IF_VERSION_MATCHES",
            "SKIP_EXT_MODULES",
            "SKIP_CP_KERNEL_HDR",
            "SKIP_UNPACKING_RAMDISK",
            "POST_DEFCONFIG_CMDS",
            "IN_KERNEL_MODULES",
            "DO_NOT_STRIP_MODULES",
            "AVB_SIGN_BOOT_IMG",
            "AVB_BOOT_PARTITION_SIZE",
            "AVB_BOOT_KEY",
            "AVB_BOOT_ALGORITHM",
            "AVB_BOOT_PARTITION_NAME",
            "MODULES_ORDER",
            "GKI_MODULES_LIST",
            "LZ4_RAMDISK",
            "LZ4_RAMDISK_COMPRESS_ARGS",
            "KMI_STRICT_MODE_OBJECTS",
            "GKI_DIST_DIR",
            "BUILD_GKI_ARTIFACTS",
            "GKI_KERNEL_CMDLINE",
            "AR",
            "ARCH",
            "BRANCH",
            "BUILDTOOLS_PREBUILT_BIN",
            "CC",
            "CLANG_PREBUILT_BIN",
            "CLANG_VERSION",
            "COMMON_OUT_DIR",
            "DECOMPRESS_GZIP",
            "DECOMPRESS_LZ4",
            "DEFCONFIG",
            "DEPMOD",
            "DTC",
            "HOSTCC",
            "HOSTCFLAGS",
            "HOSTCXX",
            "HOSTLDFLAGS",
            "KBUILD_BUILD_HOST",
            "KBUILD_BUILD_TIMESTAMP",
            "KBUILD_BUILD_USER",
            "KBUILD_BUILD_VERSION",
            "KCFLAGS",
            "KCPPFLAGS",
            "KERNEL_DIR",
            "KMI_GENERATION",
            "LC_ALL",
            "LLVM",
            "MODULES_ARCHIVE",
            "NDK_TRIPLE",
            "NM",
            "OBJCOPY",
            "OBJDUMP",
            "OBJSIZE",
            "PATH",
            "RAMDISK_COMPRESS",
            "RAMDISK_DECOMPRESS",
            "RAMDISK_EXT",
            "READELF",
            "ROOT_DIR",
            "SOURCE_DATE_EPOCH",
            "STRIP",
            "TOOL_ARGS",
            "TZ",
            "UNSTRIPPED_DIR",
            "UNSTRIPPED_MODULES_ARCHIVE",
            "USERCFLAGS",
            "USERLDFLAGS",
            "_SETUP_ENV_SH_INCLUDED",
    ):
        return True
    if build_config.startswith("BASH_FUNC_") and build_config.endswith("%%"):
        return True
    if build_config == "_":
        return True
    return False


def not_supported(build_config):
    if build_config in (
            "EXT_MODULES_MAKEFILE",
            "COMPRESS_MODULES",
            "ADDITIONAL_HOST_TOOLS",
            "POST_KERNEL_BUILD_CMDS",
            "TAGS_CONFIG",
            "EXTRA_CMDS",
            "DIST_CMDS",
            "VENDOR_RAMDISK_CMDS",
            "STOP_SHIP_TRACEPRINTK",
    ):
        return True
    return False


def create_buildozer_commands(out_file, new_env, old_env, package, target_name, common):
    pkg = f"//{package}:__pkg__"
    dist_name = f"{target_name}_dist"
    unstripped_modules_name = f"{target_name}_unstripped_modules_archive"
    images_name = f"{target_name}_images"
    dts_name = f"{target_name}_dts"
    modules_install_name = f"{target_name}_modules_install"

    # TODO skip creating targets if already existed by pre-populating existing_names
    existing_names = set()
    dist_targets = set()

    def new(type, name, new_package=package, load=True, add_to_dist=True):
        ensure_build_file(new_package)
        new_pkg = f"//{new_package}:__pkg__"
        target = f"//{new_package}:{name}"
        if target not in existing_names:
            if load:
                out_file.write(f"""
                    fix movePackageToTop|{new_pkg}
                    new_load //build/kernel/kleaf:kernel.bzl {type}|{new_pkg}
""")
            out_file.write(f"""new {type} {name}|{new_pkg}\n""")
            existing_names.add(target)
        if add_to_dist:
            dist_targets.add(target)
        return target

    target = new("kernel_build", target_name)

    out_file.write(
        f"new_load //build/bazel_common_rules/dist:dist.bzl copy_to_dist_dir|{pkg}\n")
    dist = new("copy_to_dist_dir", dist_name, load=False, add_to_dist=False)
    out_file.write(f"""set flat True|{dist}\n""")
    images = None
    modules_install = None

    target_comment = []
    dist_comment = []
    images_comment = []
    unknowns = []

    for key, value in new_env.items():
        esc_value = value.replace(" ", "\\ ")
        if is_ignored_build_config(key):
            continue
        elif not_supported(key):
            target_comment.append(f"FIXME: {key}={esc_value} not supported")
        elif key == "BUILD_CONFIG":
            out_file.write(f"""set build_config "{os.path.basename(value)}"|{target}\n""")
        elif key == "BUILD_CONFIG_FRAGMENTS":
            target_comment.append(
                f"FIXME: {key}={esc_value}: Please manually convert to kernel_build_config")
        elif key == "FAST_BUILD":
            target_comment.append(f"FIXME: {key}: Specify --config=fast in device.bazelrc")
        elif key == "LTO":
            target_comment.append(f"FIXME: {key}: Specify --lto={value} in device.bazelrc")
        elif key == "DIST_DIR":
            rel_dist_dir = os.path.relpath(value)
            out_file.write(f"""
                set dist_dir None|{dist}
                comment dist_dir FIXME:\\ or\\ dist_dir\\ =\\ "{rel_dist_dir}"|{dist}
""")
        elif key == "FILES":
            for elem in value.split():
                out_file.write(f"""add outs "{elem}"|{target}\n""")
        elif key == "EXT_MODULES":
            # FIXME add kernel_modules_install (modules_install) to EXT_MODULES
            target_comment.append(
                f"FIXME: {key}={esc_value}: Please manually convert to kernel_module")
        elif key == "KCONFIG_EXT_PREFIX":
            out_file.write(f"""set kconfig_ext "{value}"|{target}\n""")
        elif key == "UNSTRIPPED_MODULES":
            out_file.write(f"""set collect_unstripped_modules {bool(value)}|{target}\n""")
        elif key == "COMPRESS_UNSTRIPPED_MODULES":
            unstripped_modules = new("kernel_unstripped_modules_archive",
                                     {unstripped_modules_name})
            out_file.write(f"""
                set kernel_build "{target}"|{unstripped_modules}
                set kernel_modules None|{unstripped_modules}
                comment kernel_modules FIXME:\\ set\\ kernel_modules\\ to\\ the\\ list\\ of\\ kernel_module()s|{unstripped_modules}
""")
        elif key in ("ABI_DEFINITION", "KMI_ENFORCED"):
            # FIXME also ABI monitoring
            target_comment.append(
                f"FIXME: {key}={esc_value}: Please manually convert to kernel_build_abi")
        elif key == "KMI_SYMBOL_LIST":
            out_file.write(f"""set kmi_symbol_list "//{common}:android/{value}"|{target}\n""")
        elif key == "ADDITIONAL_KMI_SYMBOL_LISTS":
            kmi_symbol_lists = value.split()
            for kmi_symbol_list in kmi_symbol_lists:
                out_file.write(
                    f"""add additional_kmi_symbol_lists "//{common}:android/{kmi_symbol_list}"|{target}\n""")
        elif key in (
                "TRIM_NONLISTED_KMI",
                "GENERATE_VMLINUX_BTF",
                "KMI_SYMBOL_LIST_STRICT_MODE",
                "KBUILD_SYMTYPES",
        ):
            out_file.write(f"""set {key.lower()} {value == "1"}|{target}\n""")
        elif key == "PRE_DEFCONFIG_CMDS":
            target_comment.append(
                f"FIXME: PRE_DEFCONFIG_CMDS: Don't forget to modify to write to $OUT_DIR: https://android.googlesource.com/kernel/build/+/refs/heads/master/kleaf/docs/errors.md#defconfig-readonly")
        elif key in (
                "BUILD_BOOT_IMG",
                "BUILD_VENDOR_BOOT_IMG",
                "BUILD_DTBO_IMG",
                "BUILD_VENDOR_KERNEL_BOOT",
        ):
            images = new("kernel_images", images_name)
            out_file.write(
                f"""set {key.removesuffix("_IMG").lower()} {bool(value)}|{images}\n""")
        elif key == "SKIP_VENDOR_BOOT":
            images = new("kernel_images", images_name)
            out_file.write(f"set build_vendor_boot {not bool(value)}|{images}\n")
        elif key in ("BUILD_INITRAMFS",):
            images = new("kernel_images", images_name)
            out_file.write(f"""set {key.lower()} {value == "1"}|{images}\n""")
        elif key == "MKBOOTIMG_PATH":
            images = new("kernel_images", images_name)
            out_file.write(f"""
                set mkbootimg None|{images}
                comment mkbootimg FIXME:\\ set\\ mkbootimg\\ to\\ label\\ of\\ {esc_value}|{images}
""")
        elif key == "MODULES_OPTIONS":
            # TODO(b/241162984): Fix MODULES_OPTIONS; it should be a string
            images = new("kernel_images", images_name)
            out_file.write(f"""
                set modules_options None|{images}
                comment module_options TODO(b/241162984):\\ Support\\ MODULE_OPTIONS|{images}
""")
        elif key in (
                "MODULES_LIST",
                "MODULES_BLOCKLIST",
                "SYSTEM_DLKM_MODULES_LIST",
                "SYSTEM_DLKM_MODULES_BLOCKLIST",
                "SYSTEM_DLKM_PROPS",
                "VENDOR_DLKM_MODULES_LIST",
                "VENDOR_DLKM_MODULES_BLOCKLIST",
                "VENDOR_DLKM_PROPS",
        ):
            images = new("kernel_images", images_name)
            if os.path.commonpath(value, package) == package:
                out_file.write(
                    f"""set {key.lower()} "{os.path.relpath(value, start=package)}"|{images}\n""")
            else:
                out_file.write(f"""
                    set {key.lower()} None|{images}
                    comment {key.lower()} FIXME:\\ set\\ {key.lower()}\\ to\\ label\\ of\\ {esc_value}|{images}
""")
        elif key == "GKI_BUILD_CONFIG":
            if value == f"{common}/build.config.gki.aarch64":
                out_file.write(f"""set base_build "//{common}:kernel_aarch64"|{target}\n""")
            else:
                out_file.write(f"""
                    set base_build None|{target}
                    comment base_build FIXME:\\ set\\ base_build\\ to\\ kernel_build\\ for\\ {esc_value}|{target}
""")
        elif key == "GKI_PREBUILTS_DIR":
            target_comment.append(
                f"FIXME: {key}={esc_value}: Please\\ manually\\ convert\\ to\\ kernel_filegroup\n")
        elif key == "DTS_EXT_DIR":
            dts = new("kernel_dtstree", dts_name, new_package=value, add_to_dist=False)
            out_file.write(f"""
                set {key.lower()} "{dts}"|{target}
""")
        elif key == "BUILD_GKI_CERTIFICATION_TOOLS":
            if value == "1":
                dist_targets.add("//build/kernel:gki_certification_tools")
        elif key in old_env:
            if old_env[key] == value:
                logging.info(f"Ignoring variable {key} in environment.")
            else:
                target_comment.append(f"FIXME: Unknown in build config: {key}={esc_value}")
                unknowns.append(key)
        else:
            target_comment.append(f"FIXME: Unknown in build config: {key}={esc_value}")
            unknowns.append(key)

    for dist_target in dist_targets:
        out_file.write(f"""add data "{dist_target}"|{dist}\n""")

    if images:
        if not modules_install:
            modules_install = new("kernel_modules_install", modules_install_name)
            out_file.write(f"""
                set kernel_build "{target}"|{modules_install}
                set kernel_modules []|{modules_install}
                comment kernel_modules FIXME:\\ kernel_modules\\ should\\ include\\ the\\ list\\ of\\ kernel_module()s|{modules_install}
""")

        out_file.write(f"""
            set kernel_build "{target}"|{images}
            set kernel_modules_install "{modules_install}"|{images}
""")

    if "KERNEL_DIR" in new_env and new_env["KERNEL_DIR"] != package:
        if new_env["KERNEL_DIR"].removesuffix("/") == common:
            out_file.write(f"""
                set_if_absent srcs {DEFAULT_KERNEL_BUILD_SRCS}|{target}
                add srcs "//{common}:kernel_aarch64_sources"|{target}\n
""")
        else:
            out_file.write(f"""
                set_if_absent srcs None|{target}
                comment srcs FIXME:\\ add\\ files\\ from\\ KERNEL_DIR\\ {new_env["KERNEL_DIR"]}
""")


    target_comment_content = "\\n".join(target_comment)
    target_comment_content = target_comment_content.replace(" ", "\\ ")
    if target_comment_content:
        out_file.write(f"""comment {target_comment_content}|{target}\n""")

    dist_comment_content = "\\n".join(dist_comment)
    dist_comment_content = dist_comment_content.replace(" ", "\\ ")
    if dist_comment_content:
        out_file.write(f"""comment {dist_comment_content}|{dist}\n""")

    images_comment_content = "\\n".join(images_comment)
    images_comment_content = images_comment_content.replace(" ", "\\ ")
    if images_comment_content:
        out_file.write(f"""comment {images_comment_content}|{images}\n""")

    if unknowns:
        logging.info("Unknown variables:\n%s", ",\n".join(f'"{e}"' for e in unknowns))


def run_buildozer(buildozer, buildozer_command_path, args):
    buildozer_args = [
        buildozer, "-shorten_labels", "-f", buildozer_command_path
    ]
    if args.k:
        buildozer_args.append("-k")
    if args.stdout:
        buildozer_args.append("-stdout")
    try:
        subprocess.check_call(buildozer_args)
    except subprocess.CalledProcessError as e:
        if e.returncode != BUILDOZER_NO_CHANGES_MADE and not args.k:
            raise


def add_additional_comments(buildozer, package, target_name, common, args):
    target = f"//{package}:{target_name}"
    base_kernel_expected_comment = f"FIXME: base_kernel should be migrated to //{common}:kernel_aarch64."

    base_kernel = subprocess.check_output([buildozer, "print base_kernel", target],
                                          text=True).strip()
    base_kernel_comment = ""
    try:
        base_kernel_comment = subprocess.check_output([buildozer, "print_comment base_kernel", target],
                                                  text = True).strip()
    except subprocess.CalledProcessError:
        pass

    logging.info("base_kernel_comment = %s", base_kernel_comment)

    with tempfile.NamedTemporaryFile("w+", delete=False) as f:
        f.write(f"set_if_absent base_kernel None|{target}\n")
        if base_kernel not in (f"//{common}:kernel_aarch64", f"//{common}:kernel") and \
            base_kernel_expected_comment not in base_kernel_comment:
            esc_base_kernel_comment = base_kernel_expected_comment.replace(" ", "\\ ")
            f.write(
                f"""comment base_kernel {esc_base_kernel_comment}|{target}\n""")

        f.flush()
        f.seek(0)
        logging.info("Executing buildozer with the following commands:\n%s", f.read())
        run_buildozer(buildozer, f.name, args)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--target",
                        help="Name of target. Otherwise, infer from the name of the build.config file.")
    parser.add_argument("--log", help="log level", default="warning")
    parser.add_argument("-k",
                        help="buildozer keep going. Use when targets are already defined. There may be duplicated FIXME comments.",
                        action="store_true")
    parser.add_argument("--stdout", help="buildozer write changed BUILD file to stdout (dry run)",
                        action="store_true")
    parser.add_argument("--ack", help="path to ACK source tree", default="common")
    args = parser.parse_args()

    numeric_level = getattr(logging, args.log.upper(), None)
    if not isinstance(numeric_level, int):
        raise ValueError('Invalid log level: %s' % args.log)
    logging.basicConfig(level=numeric_level, format='%(levelname)s: %(message)s')

    buildozer = find_buildozer()

    old_env = order_dict_by_key(os.environ)
    new_env = order_dict_by_key(json.loads(subprocess.check_output(
        "source build/kernel/_setup_env.sh > /dev/null && build/kernel/kleaf/env.py",
        shell=True)))
    logging.info("Captured env: %s", json.dumps(new_env, indent=2))

    build_config = find_build_config(new_env)
    target_name = infer_target_name(args, build_config)

    package = os.path.dirname(build_config)

    with tempfile.NamedTemporaryFile("w+") as buildozer_command_file:
        create_buildozer_commands(buildozer_command_file, new_env, old_env, package, target_name,
                                  args.ack)
        buildozer_command_file.flush()
        buildozer_command_file.seek(0)
        logging.info("Executing buildozer with the following commands:\n%s",
                     buildozer_command_file.read())
        run_buildozer(buildozer, buildozer_command_file.name, args)

    if not args.stdout:
        add_additional_comments(buildozer, package, target_name, args.ack, args)


if __name__ == "__main__":
    main()
