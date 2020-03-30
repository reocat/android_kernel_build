#!/bin/bash

if [ $# -ne 1 ]; then
	echo "usage: uapi-verify.sh COMMIT"
	echo
	echo "Extract all UAPI headers from commit and check them for"
	echo "ABI changes"

	exit 1
fi

ABIDIFF=abidiff
UNIFDEF=unifdef
CC="${CROSS_COMPILE}gcc"
COMMITID=$1

# Get the file and sanitize it using the same sed script from
# scripts/headers_install.sh and run it through unifdef

get_header() {
	git show $1:$2 | sed -E -e '
	s/([[:space:](])(__user|__force|__iomem)[[:space:]]/\1/g
	s/__attribute_const__([[:space:]]|$)/\1/g
	s@^#include <linux/compiler(|_types).h>@@
	s/(^|[^a-zA-Z0-9])__packed([^a-zA-Z0-9_]|$)/\1__attribute__((packed))\2/g
	s/(^|[[:space:](])(inline|asm|volatile)([[:space:](]|$)/\1__\2__\3/g
	s@#(ifndef|define|endif[[:space:]]*/[*])[[:space:]]*_UAPI@#\1 @
	' | $UNIFDEF -U __KERNEL__ -D__EXPORTED_HEADERS__
}

# Compile the simple test app with the header $1 and put the binary in $2
do_compile() {
	echo "int main(int argc, char *argv) { return 0; }" | \
	${CC} -c -o $2 -x c -O0 -std=c90 -fno-eliminate-unused-debug-types -g -include $1 -
}

DIR=$(mktemp -d)
trap 'rm -rf $DIR' EXIT
failed=0

git diff --name-status ${COMMITID}^1..${COMMITID} | while read line; do
	status=$(echo $line | cut -d ' ' -f 1)
	file=$(echo $line | cut -d ' ' -f 2)

	# Don't check newly added files
	[ "$status" == "A" ] && continue

	# Only check files from a uapi directory
	echo $file | grep -q "uapi\/" || continue

	# If the file was deleted print a nastygram and continue
	if [ "$status" == "D" ]; then
		print "UAPI header file $file was removed\n"
		failed=1
		continue
	fi

	# Use a temporary name for the 'before' version of the header but reuse
	# the header name for the "after' version so abidiff wil tell us which
	# file failed,i.e:
	#
	# 1 data member insertion:
	# 'unsigned int naughty', at offset 192 (in bits) at toshiba.h:45:1

	PRE="${DIR}/pre-$(basename $file)"
	POST="${DIR}/$(basename $file)"

	get_header "${COMMITID}^1" $file > $PRE
	get_header "${COMMITID}" $file > $POST

	do_compile ${PRE} ${DIR}/pre.bin
	if [ $? != 0 ]; then
		echo "Couldn't build the before version of $file";
		failed=1
		continue
	fi

	do_compile ${POST} ${DIR}/post.bin
	if [ $? != 0 ]; then
		echo "Couldn't build the after version of $file";
		failed=1
		continue
	fi

	$ABIDIFF -t ${DIR}/pre.bin ${DIR}/post.bin
	if [ $? != 0]; then
		failed=1
	fi
done

exit $failed
