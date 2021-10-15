#!/usr/bin/env bash

function usage() {
	echo "USAGE: $0 [GKI_OUT_DIR]"
	echo
	echo "Compare the files used to compile a GKI kernel with those on a device kernel"
	echo
	echo "This is achieved by parsing generated .cmd files inside a compiled GKI kernel tree"
	echo "These .cmd files list the file dependencies and so give us a good idea of which files"
	echo "are used when compiling the GKI kernel."
	echo
	echo "In order to do the comparison, the following requirements must be met:"
	echo "  - Compiled GKI kernel output"
	echo "  - Device kernel tree source with the SHA of GKI kernel tree present (i.e. git diff GKI_SHA is done)"
	echo "  - GKI kernel tree source. Note: this is derived from the compiled GKI kernel output"
	echo
	echo "Limitations:"
	echo "  - Vendor kernel should have GKI kernel merged into its baseline for accurate difference"
	echo "  - Does not compare files which *would* be compiled into vmlinux in a vendor kernel build."
	echo "    For instance, if vendor defconfig selects some new static option not enabled in gki_defconfig,"
	echo "    this script would not detect that."
	echo
	echo "arguments:"
	echo "  GKI_OUT_DIR [optional]   Location of the compile GKI kernel tree. If not set, then"
	echo "                           mixed build settings are used"
}

export ROOT_DIR=$(readlink -f $(dirname $0)/../..)
cd ${ROOT_DIR}

# Save environment so we can extract environment from GKI build
OLD_ENVIRONMENT=$(mktemp)
export -p > ${OLD_ENVIRONMENT}

source "${ROOT_DIR}/build/_setup_env.sh"

GKI_OUT_DIR="$1"

if [ -z "${GKI_OUT_DIR}" ]; then
	if [ -z "${GKI_BUILD_CONFIG}" ]; then
		usage
		exit 1
	fi

	GKI_OUT_DIR=${GKI_OUT_DIR:-${COMMON_OUT_DIR}/gki_kernel}
	GKI_DIST_DIR=${GKI_DIST_DIR:-${GKI_OUT_DIR}/dist}
	GKI_ENVIRON+=" GKI_BUILD_CONFIG="
	GKI_ENVIRON+=" $(export -p | sed -n -E -e 's/.*GKI_([^=]+=.*)$/\1/p' | tr '\n' ' ')"
	GKI_ENVIRON+=" OUT_DIR=${GKI_OUT_DIR}"
	GKI_ENVIRON+=" DIST_DIR=${GKI_DIST_DIR}"

	GKI_OUT_DIR=$( env -i bash -c "source ${OLD_ENVIRONMENT}; rm -f ${OLD_ENVIRONMENT}; export ${GKI_ENVIRON}; source ${ROOT_DIR}/build/_setup_env.sh > /dev/null && echo \${OUT_DIR}" )
fi

echo "========================================================"
echo "Determining location of GKI kernel"

if [ -z "${GKI_OUT_DIR}" -o ! -e "${GKI_OUT_DIR}/init/.main.o.cmd" ]; then
	echo "ERROR: GKI kernel has not been compiled"
	echo
	usage
	exit 1
fi

GKI_KERNEL_DIR=$(grep "^source_" ${GKI_OUT_DIR}/init/.main.o.cmd | sed -E -e "s%.*:= (.*)/init/main.c$%\1%")
echo "  ${GKI_KERNEL_DIR}"

if [ ! -e "${GKI_KERNEL_DIR}" ]; then
	echo "ERROR: GKI kernel directory could not be determined: '${GKI_KERNEL_DIR}'"
	echo
	usage
	exit 1
fi

echo "========================================================"
echo "Extracting built files"
find ${GKI_OUT_DIR} -name "*.cmd" | while read dotcmd ; do
	(
		# find the line starting with source_, extract the filename from the line
		grep "^source_" $dotcmd | sed -E -e "s%.*:= (.*)$%\1%";
		# print every line after deps_ line, until there is a blank line
		awk '/^[[:blank:]]*$/ { if (in_deps) exit }
		    in_deps {print}
		    /deps_/ {in_deps = 1}' $dotcmd | \
			# post processing. expr #1 strips the backslashes, expr #2 extracts the $(wildcard file/name.c), expr #3 removes whitespace
			sed -E -e 's%\\%%g' -e 's%\$\(wildcard ([^\)]+)\)%\1%g' -e 's%[[:space:]]%%g'
	) | sed -e "s%${GKI_KERNEL_DIR}%%g" -e "s%^/%%"
# Now, sort and remove duplicates and Kconfig files here and now because realpath is costly to do hundreds/thousands of extra times
done | sort -u | grep -v Kconfig | while read srcfile ; do
	# Some dependencies are generated in the output folder: skip those
	# Some paths may be of the form arch/arm64/kernel/../boot/blah.c, resolve it using realpath
	realpath ${GKI_KERNEL_DIR}/$srcfile 2>/dev/null | sed -e "s%^${GKI_KERNEL_DIR}/%%"
done | sort -u > core_files.txt
echo "[core_files.txt]: There are $(wc -l core_files.txt) source files contributing to build in ${GKI_OUT_DIR}"

if [ "${GKI_KERNEL_DIR}" -ef "${ROOT_DIR}/${KERNEL_DIR}" ]; then
	echo "  Not a mixed build environment, skipping comparison of GKI kernel and vendor kernel"
	exit
fi

echo "========================================================"
echo "Checking Git SHA on GKI kernel and vendor kernel"
if [ ! -e "${GKI_KERNEL_DIR}/.git" ] ; then
	echo "GKI_KERNEL_DIR is not a git repository"
	exit
elif [ ! -e "${ROOT_DIR}/${KERNEL_DIR}/.git" ]; then
	echo "Device kernel (${KERNEL_DIR}) is not a git repository"
	exit
fi

GKI_SHA=$(git -C ${GKI_KERNEL_DIR} rev-parse HEAD)

if ! git -C ${ROOT_DIR}/${KERNEL_DIR} rev-parse --quiet --verify ${GKI_SHA} ; then
	echo "ERROR: Don't know how to compare GKI tree to vendor tree!"
	echo "${GKI_KERNEL_DIR} HEAD is at ${GKI_SHA}"
	echo "That commit doesn't exist on ${KERNEL_DIR}"
	exit 1
fi

if ! git -C ${ROOT_DIR}/${KERNEL_DIR} merge-base --is-ancestor ${GKI_SHA} HEAD ; then
	echo "WARNING: GKI SHA (${GKI_SHA}) is not a reachable ancestor on vendor tree, results may not be correct."
fi

echo "========================================================"
while read file; do
	if [ -e "${GKI_KERNEL_DIR}/${file}" ] && \
	   ! diff -q ${GKI_KERNEL_DIR}/${file} ${ROOT_DIR}/${KERNEL_DIR}/${file} > /dev/null ; then
		echo ${file}
	fi
done < core_files.txt > changed_files.txt
echo "[changed_files.txt]: There are $(wc -l changed_files.txt) source files changed in vendor tree (${KERNEL_DIR})"

rm -f diff.txt diff_numstat.txt
while read -r file ; do
	diff -u ${GKI_KERNEL_DIR}/${file} ${ROOT_DIR}/${KERNEL_DIR}/${file} >> diff.txt

	lines_added=$(diff ${GKI_KERNEL_DIR}/${file} ${ROOT_DIR}/${KERNEL_DIR}/${file} | tail -n +3 | grep "^+" | wc -l)
	lines_removed=$(diff ${GKI_KERNEL_DIR}/${file} ${ROOT_DIR}/${KERNEL_DIR}/${file} | tail -n +3 | grep "^-" | wc -l)
	printf "%4s %4s %s\n" $lines_added $lines_removed $file >> diff_numstat.txt
done < changed_files.txt

