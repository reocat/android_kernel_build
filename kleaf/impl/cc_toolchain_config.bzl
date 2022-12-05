load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "tool_path")

def _aarch64_clang_config(ctx):
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
        toolchain_identifier = "aarch64_clang_id",
        host_system_name = "local",
        target_system_name = "local",
        target_cpu = "aarch64",
        target_libc = "unknown",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
    )

aarch64_clang_config = rule(
    implementation = _aarch64_clang_config,
    attrs = {},
    provides = [CcToolchainConfigInfo],
)
