# TODO migrate these to extensions
load("//build/kernel/kleaf:key_value_repo.bzl", "key_value_repo")

common_kernel_package = "//common"  # FIXME

key_value_repo(
    name = "kernel_toolchain_info",
    srcs = ["{}:build.config.constants".format(common_kernel_package)],
    additional_values = {
        "common_kernel_package": common_kernel_package,
    },
)

load(
    "//build/kernel/kleaf/impl:local_repository.bzl",
    "new_kleaf_local_repository",
)

new_kleaf_local_repository(
    name = "prebuilt_ndk",
    build_file = "build/kernel/kleaf/ndk.BUILD",
    path_candidates = [
        # do not sort
        "prebuilts/ndk-r26",
        # TODO(b/309695443): Delete once all branches have switched to r26
        "prebuilts/ndk-r23",
    ],
)

load("//build/kernel/kleaf/impl:kleaf_host_tools_repo.bzl", "kleaf_host_tools_repo")

kleaf_host_tools_repo(
    name = "kleaf_host_tools",
    host_tools = [
        "bash",
        "perl",
        "rsync",
        "sh",
        # For BTRFS (b/292212788)
        "find",
    ],
)
