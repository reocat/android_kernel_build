load(
    "//build/kernel/kleaf:kernel_impl.bzl",
    KernelFilesInfo_impl = "KernelFilesInfo",
    kernel_build_config_impl = "kernel_build_config",
    kernel_build_impl = "kernel_build",
    kernel_compile_commands_impl = "kernel_compile_commands",
    kernel_dtstree_impl = "kernel_dtstree",
    kernel_filegroup_impl = "kernel_filegroup",
    kernel_images_impl = "kernel_images",
    kernel_kythe_impl = "kernel_kythe",
    kernel_module_impl = "kernel_module",
    kernel_modules_install_impl = "kernel_modules_install",
)

kernel_build_config = kernel_build_config_impl
KernelFilesInfo = KernelFilesInfo_impl
kernel_build = kernel_build_impl
kernel_dtstree = kernel_dtstree_impl
kernel_module = kernel_module_impl
kernel_modules_install = kernel_modules_install_impl
kernel_images = kernel_images_impl
kernel_filegroup = kernel_filegroup_impl
kernel_compile_commands = kernel_compile_commands_impl
kernel_kythe = kernel_kythe_impl
