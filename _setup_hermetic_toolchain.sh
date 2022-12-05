
# List of prebuilt directories shell variables to incorporate into PATH
prebuilts_paths=(
LINUX_GCC_CROSS_COMPILE_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_ARM32_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_COMPAT_PREBUILTS_BIN
CLANG_PREBUILT_BIN
LZ4_PREBUILTS_BIN
DTC_PREBUILTS_BIN
LIBUFDT_PREBUILTS_BIN
BUILDTOOLS_PREBUILT_BIN
)

# Have host compiler use LLD and compiler-rt.
LLD_COMPILER_RT="-fuse-ld=lld --rtlib=compiler-rt"
if [[ -n "${NDK_TRIPLE}" ]]; then
  NDK_DIR=${ROOT_DIR}/prebuilts/ndk-r23
  if [[ ! -d "${NDK_DIR}" ]]; then
    # Kleaf/Bazel will checkout the ndk to a different directory than
    # build.sh.
    NDK_DIR=${ROOT_DIR}/external/prebuilt_ndk
    if [[ ! -d "${NDK_DIR}" ]]; then
      echo "ERROR: NDK_TRIPLE set, but unable to find prebuilts/ndk." 1>&2
      echo "Did you forget to checkout prebuilts/ndk?" 1>&2
      exit 1
    fi
  fi
  USERCFLAGS="--target=${NDK_TRIPLE} "
  USERCFLAGS+="--sysroot=${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot "
  # Some kernel headers trigger -Wunused-function for unused static functions
  # with clang; GCC does not warn about unused static inline functions. The
  # kernel sets __attribute__((maybe_unused)) on such functions when W=1 is
  # not set.
  USERCFLAGS+="-Wno-unused-function "
  # To help debug these flags, consider commenting back in the following, and
  # add `echo $@ > /tmp/log.txt` and `2>>/tmp/log.txt` to the invocation of $@
  # in scripts/cc-can-link.sh.
  #USERCFLAGS+=" -Wl,--verbose -v"
  # We need to set -fuse-ld=lld for Android's build env since AOSP LLVM's
  # clang is not configured to use LLD by default, and BFD has been
  # intentionally removed. This way CC_CAN_LINK can properly link the test in
  # scripts/cc-can-link.sh.
  USERLDFLAGS="${LLD_COMPILER_RT} "
  USERLDFLAGS+="--target=${NDK_TRIPLE} "
else
  USERCFLAGS="--sysroot=/dev/null"
fi
export USERCFLAGS USERLDFLAGS

if [ "${HERMETIC_TOOLCHAIN:-0}" -eq 1 ]; then
  HOST_TOOLS=${OUT_DIR}/host_tools
  rm -rf ${HOST_TOOLS}
  mkdir -p ${HOST_TOOLS}
  for tool in \
      bash \
      git \
      install \
      perl \
      rsync \
      sh \
      tar \
      ${ADDITIONAL_HOST_TOOLS}
  do
      ln -sf $(which $tool) ${HOST_TOOLS}
  done
  PATH=${HOST_TOOLS}

  # use relative paths for file name references in the binaries
  # (e.g. debug info)
  export KCPPFLAGS="-ffile-prefix-map=${ROOT_DIR}/${KERNEL_DIR}/= -ffile-prefix-map=${ROOT_DIR}/="

  # set the common sysroot
  sysroot_flags+="--sysroot=${ROOT_DIR}/build/kernel/build-tools/sysroot "

  # add openssl (via boringssl) and other prebuilts into the lookup path
  cflags+="-I${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/include "

  # add openssl and further prebuilt libraries into the lookup path
  ldflags+="-Wl,-rpath,${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/lib64 "
  ldflags+="-L ${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/lib64 "
  ldflags+=${LLD_COMPILER_RT}

  export HOSTCFLAGS="$sysroot_flags $cflags"
  export HOSTLDFLAGS="$sysroot_flags $ldflags"
fi

for prebuilt_bin in "${prebuilts_paths[@]}"; do
    prebuilt_bin=\${${prebuilt_bin}}
    eval prebuilt_bin="${prebuilt_bin}"
    if [ -n "${prebuilt_bin}" ]; then
        # Mitigate dup paths
        PATH=${PATH//"${ROOT_DIR}\/${prebuilt_bin}:"}
        PATH=${ROOT_DIR}/${prebuilt_bin}:${PATH}
    fi
done
export PATH

unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PYTHONHOME
unset PYTHONSTARTUP

export HOSTCC HOSTCXX CC LD AR NM OBJCOPY OBJDUMP OBJSIZE READELF STRIP AS

tool_args=()

# LLVM=1 implies what is otherwise set below; it is a more concise way of
# specifying CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy <etc>, for
# newer kernel versions.
if [[ -n "${LLVM}" ]]; then
  tool_args+=("LLVM=1")
  # Reset a bunch of variables that the kernel's top level Makefile does, just
  # in case someone tries to use these binaries in this script such as in
  # initramfs generation below.
  HOSTCC=clang
  HOSTCXX=clang++
  CC=clang
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  OBJSIZE=llvm-size
  READELF=llvm-readelf
  STRIP=llvm-strip
else
  if [ -n "${HOSTCC}" ]; then
    tool_args+=("HOSTCC=${HOSTCC}")
  fi

  if [ -n "${CC}" ]; then
    tool_args+=("CC=${CC}")
    if [ -z "${HOSTCC}" ]; then
      tool_args+=("HOSTCC=${CC}")
    fi
  fi

  if [ -n "${LD}" ]; then
    tool_args+=("LD=${LD}" "HOSTLD=${LD}")
  fi

  if [ -n "${NM}" ]; then
    tool_args+=("NM=${NM}")
  fi

  if [ -n "${OBJCOPY}" ]; then
    tool_args+=("OBJCOPY=${OBJCOPY}")
  fi
fi

if [ -n "${LLVM_IAS}" ]; then
  tool_args+=("LLVM_IAS=${LLVM_IAS}")
  # Reset $AS for the same reason that we reset $CC etc above.
  AS=clang
fi

if [ -n "${DEPMOD}" ]; then
  tool_args+=("DEPMOD=${DEPMOD}")
fi

if [ -n "${DTC}" ]; then
  tool_args+=("DTC=${DTC}")
fi

export TOOL_ARGS="${tool_args[@]}"