#!/bin/bash

# Usage:
# build/abi/dump_uapi_headers_abi.sh <headers dir> <output>

HEADERS_DIR=$1
OUT_FILE=$2

if [ -z "$HEADERS_DIR" -o -z "$OUT_FILE" ]; then
	echo "Usage: build/abi/dump_uap_headers_abi.sh <headers dir> <output file>"
	exit 1
fi

# Test to see if the compiler supports the flag we need
$CC -x c -o /dev/null -S -g -fno-eliminate-unused-debug-types /dev/null 2> /dev/null
if [ $? != 0 ]; then
	echo "${CC} does not not support -fno-eliminate-unused-debug-types"
	exit 1
fi

# This is the exclude list from linux-5.6. These are known to not compile
# as standalone

exclude="asm/shmbuf.h"
exclude+="|asm/signal.h"
exclude+="|asm/ucontext.h"
exclude+="|drm/vmwgfx_drm.h"
exclude+="|linux/am437x-vpfe.h"
exclude+="|linux/android/binder.h"
exclude+="|linux/android/binderfs.h"
exclude+="|linux/coda.h"
exclude+="|linux/elfcore.h"
exclude+="|linux/errqueue.h"
exclude+="|linux/fsmap.h"
exclude+="|linux/hdlc/ioctl.h"
exclude+="|linux/ivtv.h"
exclude+="|linux/kexec.h"
exclude+="|linux/matroxfb.h"
exclude+="|linux/nfc.h"
exclude+="|linux/omap3isp.h"
exclude+="|linux/omapfb.h"
exclude+="|linux/patchkey.h"
exclude+="|linux/phonet.h"
exclude+="|linux/reiserfs_xattr.h"
exclude+="|inux/sctp.h"
exclude+="|linux/signal.h"
exclude+="|linux/sysctl.h"
exclude+="|linux/usb/audio.h"
exclude+="|linux/v4l2-mediabus.h"
exclude+="|linux/v4l2-subdev.h"
exclude+="|linux/videodev2.h"
exclude+="|linux/vm_sockets.h"
exclude+="|sound/asequencer.h"
exclude+="|sound/asoc.h"
exclude+="|sound/asound.h"
exclude+="|sound/compress_offload.h"
exclude+="|sound/emu10k1.h"
exclude+="|sound/sfnt_info.h"
exclude+="|xen/evtchn.h"
exclude+="|xen/gntdev.h"
exclude+="|xen/privcmd.h"

# These additional headers need to be excluded from the unified binary
if [ "$ARCH" == "x86_64" ]; then
	exclude+="|asm/unistd_32.h"
	exclude+="|asm/unistd_x32.h"
	exclude+="|asm/posix_types_32.h"
	exclude+="|asm/posix_types_x32.h"
fi

# There can be only one (endian)
exclude+="|byteorder/big_endian.h"

# This conflicts with linux/in.h
exclude+="|linux/uio.h"
# These include linux/uio.h
exclude+="|linux/target_core_user.h"
exclude+="|linux/netfilter/nfnetlink_cthelper.h"

# Build a single test file with all of the uapi headers
build_test_code()
{
	for file in $(find ${HEADERS_DIR} -name *.h); do
		# Skip excluded files
		echo $file | egrep -q "($exclude)$" && continue
		# Skip everything in asm-generic because asm includes it anyway
		echo $file | egrep -q "asm-generic\/" && continue

		# Pull off the prefix and include it in the test file
		echo "#include <${file#${HEADERS_DIR}}>"
	done

	echo "int main(int argc, char **argv) { return 0; }"
}

tmpdir=$(mktemp -d)
trap 'rm -rf $tmpdir' EXIT

# Make some placeholder includes to fool the few uapi headers that include
# (but don't need) system headers
mkdir -p $tmpdir/sys
mkdir -p $tmpdir/arpa

touch $tmpdir/sys/time.h
touch $tmpdir/sys/ioctl.h
touch $tmpdir/arpa/inet.h

build_test_code > $tmpdir/uapi-headers.c

${CC} -c -o $tmpdir/uapi-headers.o -x c -O0 -std=c90 -isystem $tmpdir \
-I ${HEADERS_DIR} -fno-eliminate-unused-debug-types -g $tmpdir/uapi-headers.c
OUT=$?

if [ $OUT != 0 ]; then
	exit $OUT
fi

# Run abidw on the library and output the results
abidw --no-corpus-path --load-all-types --no-comp-dir-path \
--out-file ${OUT_FILE} $tmpdir/uapi-headers.o
