export ANDROID_GCOV_KERNEL_DIR=common
export ANDROID_GCOV_TARGET=android12-5.10
export ANDROID_GCOV_COMMONTARGET=common12-5.10
export ANDROID_GCOV_SUBTARGET=common
export ANDROID_GCOV_SUBSUBTARGET=

export ANDROID_GCOV_KERNEL_TOP=$(realpath $(dirname $0)/../..)

export ANDROID_GCOV_KERNEL_PATH=$ANDROID_GCOV_KERNEL_TOP/$ANDROID_GCOV_KERNEL_DIR

export ANDROID_GCOV_LLVM_BIN=$ANDROID_GCOV_KERNEL_TOP/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin/llvm-cov

export ANDROID_GCOV_FETCHER=android_gather_on_test.sh

export ANDROID_GCOV_PATH=/data/local/tmp/gcov
export ANDROID_GCOV_COVERAGE_COMPRESSED=$ANDROID_GCOV_PATH/coverage.tar.gz
