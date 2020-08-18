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

blacklist="asm/shmbuf.h"
blacklist+="|asm/signal.h"
blacklist+="|asm/ucontext.h"
blacklist+="|drm/vmwgfx_drm.h"
blacklist+="|linux/am437x-vpfe.h"
blacklist+="|linux/android/binder.h"
blacklist+="|linux/android/binderfs.h"
blacklist+="|linux/coda.h"
blacklist+="|linux/elfcore.h"
blacklist+="|linux/errqueue.h"
blacklist+="|linux/fsmap.h"
blacklist+="|linux/hdlc/ioctl.h"
blacklist+="|linux/ivtv.h"
blacklist+="|linux/kexec.h"
blacklist+="|linux/matroxfb.h"
blacklist+="|linux/nfc.h"
blacklist+="|linux/omap3isp.h"
blacklist+="|linux/omapfb.h"
blacklist+="|linux/patchkey.h"
blacklist+="|linux/phonet.h"
blacklist+="|linux/reiserfs_xattr.h"
blacklist+="|inux/sctp.h"
blacklist+="|linux/signal.h"
blacklist+="|linux/sysctl.h"
blacklist+="|linux/usb/audio.h"
blacklist+="|linux/v4l2-mediabus.h"
blacklist+="|linux/v4l2-subdev.h"
blacklist+="|linux/videodev2.h"
blacklist+="|linux/vm_sockets.h"
blacklist+="|sound/asequencer.h"
blacklist+="|sound/asoc.h"
blacklist+="|sound/asound.h"
blacklist+="|sound/compress_offload.h"
blacklist+="|sound/emu10k1.h"
blacklist+="|sound/sfnt_info.h"
blacklist+="|xen/evtchn.h"
blacklist+="|xen/gntdev.h"
blacklist+="|xen/privcmd.h"

# These additional headers need to be excluded from the unified binary
if [ "$ARCH" == "x86_64" ]; then
	blacklist+="|asm/unistd_32.h"
	blacklist+="|asm/unistd_x32.h"
	blacklist+="|asm/posix_types_32.h"
	blacklist+="|asm/posix_types_x32.h"
fi

# There can be only one (endian)
blacklist+="|byteorder/big_endian.h"

# This conflicts with linux/in.h
blacklist+="|linux/uio.h"
# These include linux/uio.h
blacklist+="|linux/target_core_user.h"
blacklist+="|linux/netfilter/nfnetlink_cthelper.h"

# Build a single test file with all of the uapi headers
build_test_code()
{
	for file in $(find ${HEADERS_DIR} -name *.h); do
		# Skip blacklisted files
		echo $file | egrep -q "($blacklist)$" && continue
		# Skip everything in asm-generic because asm includes it anyway
		echo $file | egrep -q "asm-generic\/" && continue

		# Pull off the prefix and include it in the test file
		echo "#include <${file#${HEADERS_DIR}}>"
	done

	echo "int main(int argc, char **argv) { return 0; }"
}

tmpdir=$(mktemp -d)
trap 'rm -rf $tmpdir' EXIT

# Make some dummy includes to fool the few uapi headers that include system
# headers
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
