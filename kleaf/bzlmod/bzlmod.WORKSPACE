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
