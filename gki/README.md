GKI Tools for Android Kernels
=============================

Overview
--------

This directory contains helpful tools that may be used to aid in the
development of modularized drivers.

add_EXPORT_SYMBOLS_GPL
----------------------

    USAGE: add_EXPORT_SYMBOL_GPL [--no-skip-arch] < kernel_build_error_log
           add_EXPORT_SYMBOL_GPL [--no-skip-arch] kernel_build_error_log
           grep /<module>[.]ko build_error_log | add_EXPORT_SYMBOL_GPL [--no-skip-arch]
           vi `add_EXPORT_SYMBOL_GPL [--no-skip-arch] < kernel_build_error_log`

To acquire the kernel_build_error_log eg:

    $ ./build_sm8250.sh -j50 2>&1 | tee kernel_build_error_log

To only create commit related to symbols needed for cam_spec.ko module:

    $ grep /cam_spec[.]ko kernel_build_error_log | add_EXPORT_SYMBOL_GPL

To only create commit related to a specific list of symbols, there is
the option to land just the symbols, no spaces, one per line, into a
manufactured or edited kernel_build_error_log and feed that to the script.

The script will only affect the current directory level and downward,
this allows one to segregate the adjusted content.  Any symbols that
are needed outside the range of that directory will result in errors
and the git commit phase will not be performed.

Add EXPORT_SYMBOL_GPL for any noted missing symbols, output the list of files
modified to stdout (so it can be passed to an editor command line should you
need to check or adjust the results). Automatically commit the list of files
into git.

Deals as simply as it can to handle \_\_trace\_\<symbols>, sorting the result.

Keep in mind exports can change, be added or subtracted, and that preliminary
work may expose or remove required symbols to resolve during later work.  As
such this script only adds, so you may need to revert the results and try
again to get the most up to date set.  By making this part automated it can
deal with the tens or thousands of exports that need to be discovered or
added.  If you need to adjust a subsystem, run this script in the subsystem
directory, and it will only adjust from that point downwards leaving other
higher up trees alone.

add_MODULE_LICENSE
------------------

    USAGE: add_MODULE_LICENSE < kernel_build_error_log
           add_MODULE_LICENSE kernel_build_error_log

Add MODULE_LICENSE to all the files.

Must be performed in the root directory.

find_circular
-------------

    USAGE: find_circular [dir]

Call this when depmod breaks down, or when one needs a list of the symbols
implicated in the circular dependency.

Search current or dir directory for all kernel modules.  Itemize what they
export, and what they import.  Discover links and report who fulfills them.
Report any first order circular relationships and the symbols that got us
into the situation.

Standard output is of the form:

module1.ko(symbols) -> module2.ko(symbols) -> module1.ko

Leaves an annotated modules.dep file in the specified directory.

device_snapshot
---------------

    USAGE: device_snapshot [-s <serialno>] [-D] [-f [<input>]] [-F [-o <output> [-d <input>]]]

Collect filtered /dev and /sys details, along with dmesg and probe list.

-o \<output> will drop the collection into a set of files, but will not
overrite existing content.  -F will overwrite.

-D will wait for the display

if \<output> is empty ('' or last option), will not collect dmesg or probe
list.  If no -o option is specified, then \<output> will be default of -
(stdout) and all pieces will go to the standard output separated by a cut
and snip header.  If specified, \<output> will contain the filtered /dev/
and /sys/ dumps, \<output>.probed the subset filter of just the probed drivers,
\<output>.dmesg the kernel logs and \<output>.config the uncompressed
/proc/config.gz.

-d \<input> will take the dropped collection specified to -o \<output> and
produce a diff -U1 output compared against the \<input>.

-f \<input> allows one to utilize the filter to an existing find /dev /sys
output from a device.  No dmesg will be collected.

-s \<serialno> will allow one to specify a device to connect to when multiples
are available, otherwise will default to one available or ANDROID_SERIAL
environment variable.

In your local build/flash/boot script for tight development cycles, add

    SEQ=`for i in out/${DEFAULT_BUILD}.snapshot.[0-9]*; do
           echo ${i#out/${DEFAULT_BUILD}.snapshot.}
         done |
         sed 's/^0*//' |
         grep -v 0-9 |
         tr -d .[:alpha:] |
         sort -nu |
         tail -1` &&
    NEWSEQ=$((${SEQ:-0}+1)) &&
    NEWSEQ=`printf "%03u" ${NEWSEQ}`
    if [ -z "${SEQ}" ]; then
      private/msm-google/scripts/gki/device_snapshot \
        -o out/${DEFAULT_BUILD}.snapshot.${NEWSEQ}
    else
      SEQ=`printf "%03u" ${SEQ}`
      private/msm-google/scripts/gki/device_snapshot \
        -o out/${DEFAULT_BUILD}.snapshot.${NEWSEQ} \
        -d out/${DEFAULT_BUILD}.snapshot.${SEQ}
    fi

instrument_module_init
----------------------
    USAGE: instrument_module_init [dir|file]

Add debug instrumentation to module_init and probe functions.

gki-cherry-pick
---------------
    USAGE: gki-cherry-pick [-h|--help] \
               [[[-b|--bug] <bug>]|<bug>]... \
               [[[-k|--kernel] <gitdir>[:<branch>]]|<gitdir>[:<branch>]]... \
               [[-a|--add] <filename>]... \
               [[-r|--rename] <oldfilename> <newfilename>]... \
               [--include-all|[[-x|--exclude] <filename>]...] \
               [[[[-s|--sha] <sha>]|<sha>]... \
                 [[-q|--skip-squash] [<sha>|all]]... | \
                < <patchfile>] \
               [[-c|--cherry-picked] <sha>]... \
               [--upstream]

Outputs are in kernel _gitdir_/_branch_split.patch, existing files are
overwritten.  File then can be fed to 'git am --3way --keep'
(or 'git am -3 -k split.patch' for short) while in the specified kernel
directory tree.  It is recommended to review the split.patch file to adjust
fragments accordingly before pushing, since the filtration is coarse based on
--add, and tree content so that core system or arch code is adjusted, but
driver code not present is not in partial cherry pick adjustments.  Since GKI
on the core system side is about ABI, code fragments should be evaluated as to
whether they are necessary, since they form a functional and hidden ABI
behavior in the alteration of paths taken.

Helpful when taking cherry picks to determine which portions contribute to ABI
(upstream) and which ones do not (device only).  Not the be all and end all but
should help managing the focus on what goes into the kernel.org or
android-common kernel, and which should stay where they belong in the driver
or device specific code in the kernel.

Take the list of shas and split them up based on which kernel their
contribution should be made to.  The patches may also be split up into partials
that overlap the available files in the tree.  Beware of the partials, refer to
their host commit to be sure it is what you want.  The tool makes sure they are
applied in the same order as the host tree they came from to mimimize conflict
resolution issues.

Another useful side effect of this tool is the identification of the candidate
commits that constitude squashes (multiple commits merged into one) or blobs
(copies of selected files).  It may be recommended to edit the split.path file
to stop at the first one that needs unquashing, and then redoe the analysis at
that point to develop a new split.patch with the itemized unsquashed series.

-h|--help *
    This help.

-b|--bug _bug_ *
    Add a bug number to the new commit footer.

-k|--kernel _gitdir_[:_branch_] *
    Directory and optional branch where the kernel is found.  There must be
    more than two directories specified for this patch to be of any use, even
    if the intent is that the commits come from one tree, and are auto merged
    (or cherry-pick) to another.

-r|--rename _oldfilename_ _newfilename_ *
    Rename files specified in the patch before they are evaluated.  This helps
    when a file needlesly overlaps upstream content and should really be
    standalone.  Also required because unlike the real git -x cherry-pick, this
    tool is incapable of determining how a file got renamed over time, and
    could very well drop adjustments.  Dropping the adjustments turns into a
    partial cherry pick with a clear list of what was, and what was not
    adjusted.

-a|--add _name_ *
    Ensure that this file gets added even if not present in the recipient
    tree.

-x|--exclude _filename_ *
    Exclude the named files from the patches, if not specified or with the key
    "arch" then will exclude some common non-Android cpu architectures.

--include-all
    Do not exclude any named files. Exclusive of --exclude above.

-s|--sha _sha_ *
    The sha commit to evaluate, 6-40 characters each. If non specified, then a
    'git format-patch --keep-subject' single patch content is expected
    supplied to stdin.  For stdin, the tool just looks after formatting
    and filtering the commit.

-c|--cherry-picked _sha_ *
    A root squashed cherry pick commit sha to reference in the commit
    messages only, typically added when a squashed commit is expanded to a
    series of original commits.  Only adds lines to the commit message,
    however it will investigate if it can find the full sha in the supplied
    _gitdir_s if supplied sha is shortened.

-q|--skip-squash _sha_ *
    Skip checking for a possible squash for this sha in the collected
    information.  "all" or "\*" turns off squash detection for all.
    Will save some time if there is no desire or intent to unsquash the sha.

--upstream *
    Use 'UPSTREAM:' instead of 'ANDROID: GKI:' for subject prefix.

unpack_ksyms
---------------
    USAGE: unpack_ksyms [help|-h|--help]
           unpack_ksyms [--no-clang-format] [--symtypes] [--no-clang-format] \
                        [filename|< filename]
           unpack_ksyms [--no-clang-format] diff \
                        <symbol> <kernel_out_dir> <kernel_out_dir>

Canonicalize various forms of genksym data into an easier to grok content.

If filename is of form \*.symtypes, then will expand that format, otherwise the
genksym dump format (willmcvicker@google.com).  If no filename supplied, will
assume genksym dump format.

For the diff command, the assumption is both kernels are built with
exported KBUILD_SYMTYPES=1, so the tool will search both supplied kernel
output directories for the symbol's associated .symtypes files and unpack
them, then compare them.
