load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "tool_path")

def _impl(ctx):
    # From _setup_env.sh
    # TODO: Think of a way to not sync this list?
    #  HOSTCC=clang
    #  HOSTCXX=clang++
    #  CC=clang
    #  LD=ld.lld
    #  AR=llvm-ar
    #  NM=llvm-nm
    #  OBJCOPY=llvm-objcopy
    #  OBJDUMP=llvm-objdump
    #  OBJSIZE=llvm-size
    #  READELF=llvm-readelf
    #  STRIP=llvm-strip

    # For android arm64:
    # NDK_TRIPLE=aarch64-linux-android31

    # Using a shell script to
    # redirect the binary; see
    # https://github.com/bazelbuild/bazel/issues/8438

    # TODO /bin/false?

    tool_paths = [
        tool_path(
            name = "gcc",
            path = "cc_toolchain_redirect/clang",
        ),
        tool_path(
            name = "ld",
            path = "/usr/bin/ld",
        ),
        tool_path(
            name = "ar",
            path = "/usr/bin/ar",
        ),
        tool_path(
            name = "cpp",
            path = "/bin/false",
        ),
        tool_path(
            name = "gcov",
            path = "/bin/false",
        ),
        tool_path(
            name = "nm",
            path = "/bin/false",
        ),
        tool_path(
            name = "objdump",
            path = "/bin/false",
        ),
        tool_path(
            name = "strip",
            path = "/bin/false",
        ),
    ]
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = ctx.attr.toolchain_identifier,
        target_system_name = "local",
        target_cpu = ctx.attr.target_cpu,
        target_libc = "unknown",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
    )

clang_config = rule(
    implementation = _impl,
    attrs = {
        "target_cpu": attr.string(),
        "toolchain_identifier": attr.string(),
    },
    provides = [CcToolchainConfigInfo],
)
