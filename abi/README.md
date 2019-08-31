ABI Monitoring for Android Kernels
==================================

Overview
--------
In order to stabilize the in-kernel ABI of Android Kernels, the ABI Monitoring
tooling has been created to collect and compare ABI representations from
existing Kernel Binaries (vmlinux + modules). The tools can be used to track
and mitigate changes to said ABI. This document describes the tooling, the
process of collecting and analyzing ABI representations and how such
representations can be used to ensure stability of the in-kernel ABI.  Lastly,
this documents gives some details about the process of contributing changes to
Android Kernels in AOSP that affect the monitored ABI.

This directory contains the specific tools to operate ABI analysis. It is
supposed to be used as part of the build scripts that this repository provides
(see `../build_abi.sh`).

Process Description
-------------------
Analyzing the Kernel's ABI is done in multiple steps. Most of them can be
automated:

 1. Acquire the toolchain, build scripts and kernel sources through `repo`
 2. Provide any prerequisites (e.g. libabigail)
 3. Build the kernel and its ABI representation
 4. Analyze ABI differences between the build and a reference
 5. Update the ABI representation (if required)


 5. Extract the ABI representation from the Kernel and the built modules
 6. Analyze ABI differences among different kernel builds

The following instructions are working for any kernel that can be built using
a supported toolchain (i.e. a prebuilt Clang toolchain). There exist [`repo`
manifests](https://android.googlesource.com/kernel/manifest/+refs) for all
Android Common Kernel branches as well as for some upstream branches (e.g.
upstream-linux-4.19.y) and several device specific kernels that ensure the
correct toolchain.


Using the ABI Monitoring tooling
--------------------------------

### 1. Acquire the toolchain, build scripts and kernel sources through repo

Toolchain, build scripts (i.e. these scripts) and kernel sourcs can be acquired
with `repo`. For a detailed documentation, please refer to the corresponding
documentation on
[source.android.com](https://source.android.com/setup/build/building-kernels).

To illustrate the process, the following steps use `common-android-mainline`,
an Android Kernel branch that is kept up-to-date with the upstream Linux
releases and release candidates. In order to obtain this branch via `repo`,
execute

    $ repo init -u https://android.googlesource.com/kernel/manifest -b common-android-mainline
    $ repo sync

### 2. Provide any prerequisites

> **NOTE**
>
> Googlers might want to follow the steps in
> [go/kernel-abi-monitoring](http://go/kernel-abi-monitoring) to use prebuilt
> binaries and proceed to the next step.

The ABI tooling makes use of [libabigail](https://sourceware.org/libabigail/),
a library (and some tools) to analyze binaries in regards to their ABI. As of
today, the libabigail installation is not provided as part of AOSP; neither as
source distribution nor as prebuilt binaries. In order to use the tooling,
users are required to provide a functional libabigail installation. The
released version of your Linux distribution might not be a supported one, hence
the recommended way is to use the `bootstrap` script that can be found in this
directory. It automates the process of acquiring and building a valid
libabigail distribution and needs to be executed without any arguments:

    $ build/abi/bootstrap

The script `bootstrap` will ensure the following system prerequisites are
installed along with their dependencies:

 - autoconf
 - libtool
 - libxml2-dev
 - pkg-config
 - python3

> At the moment, only apt based package managers are supported, but `bootstrap`
> provides some hints to help users that have other package managers.

The script continues with acquiring the sources for the correct versions of
*elfutils* and *libabigail* and will build the required binaries. At the very
end the script will print instructions how to add the binaries to the local
`${PATH}` to be used by the remaining utilities. The output looks like:

    Note: Export following environment before running the executables:

    export PATH="/src/kernel/build/abi/abigail-inst/d7ae619f/bin:${PATH}"
    export LD_LIBRARY_PATH="/src/kernel/build/abi/abigail-inst/d7ae619f/lib:/src/kernel/build/abi/abigail-inst/d7ae619f/lib/elfutils:${LD_LIBRARY_PATH}"


> **NOTE**
>
> It is probably a good idea to write down these instructions to reuse the
> prebuilt binaries in a later session.

Please follow the instructions to enable the prerequisites in your environment.

### 3. Build the kernel and its ABI representation

At this point all necessary steps to be able to build a kernel with the correct
toolchain and to extract an ABI representation from its binaries (vmlinux +
modules) have been completed.

Similar to the usual Android Kernel build process (using `build.sh`), this step
requires to run `build_abi.sh`.

    $ BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh

> **NOTE**
>
> `build_abi.sh` makes use of `build.sh` and therefore accepts the same
> environment variables to customize the build. It also *requires* the same
> variables that would need to be passed to `build.sh`, such as BUILD_CONFIG.

That builds the Kernel and extracts ABI representation into the `out`
directory, in this case `out/android-mainline/dist/abi-<id>.xml` and
`out/android-mainline/dist/abi.xml` is a symbolic link to the aforementioned.
`id` is currently computed from executing `git describe` against the kernel
source tree.

### 4. Analyze ABI differences between the build and a reference representation

`build_abi.sh` is capable of analyzing and reporting any detected ABI
differences if it is aware of a location of such a reference. For that the
environment variable `ABI_DEFINITION` can be used, pointing to a reference file
relative to the kernel source tree. `ABI_DEFINITION` can be specified via the
command line or (more commonly) as a value in the *build.config*. E.g.

    $ BUILD_CONFIG=common/build.config.gki.aarch64      \
      ABI_DEFINITION=abi_gki_aarch64.xml                \
      build/build_abi.sh


The `build.config.gki.aarch64` that was used above, defines such a reference
file (as *abi_gki_aarch64.xml*) and therefore the analysis has already been
completed with the previous step. If an abidiff has been done, `build_abi.sh`
will print the location of the report and will also report if any ABI breakage
had been detected. It will terminate with a non-zero exit code if breakages
have been detected.

### 5. Update the ABI representation (if required)

To update the ABI dump, `build_abi.sh` can be invoked with the `--update` flag.
It will update the corresponding abi.xml file that is defined via the
build.config. It might be useful to invoke the script also with
`--print-report` to print the differences the update cleans up. That
information is useful in the commit message when updating the abi.xml in the
source control.

Working with the lower level ABI tooling
----------------------------------------

Most users will need to use `build_abi.sh` only. In some cases, it might be
necessary to work with the lower level ABI tooling directly. There are
currently two commands, `dump_abi` and `diff_abi` that are available to collect
and compare ABI files. This commands are used by `build_abi.sh` and their usage
is documented in the following sections.

### Creating ABI dumps from kernel trees

Provided a linux kernel tree with built vmlinux and kernel modules, the tool
`dump_abi` creates an ABI representation using the selected abi tool. As of now
there is only one option: 'libabigail' (default). A sample invocation looks as
follows:

    $ dump_abi --linux-tree path/to/out --out-file /path/to/abi.xml

The file `abi.xml` will contain a combined textual ABI representation that can
be observed from vmlinux and the kernel modules in the given directory. This
file might be used for manual inspection, further analysis or as a reference
file to enforce ABI stability.

### Comparing ABI dumps

ABI dumps created by `dump_abi` can be compared with `diff_abi`. Ensure to use
the same abi-tool for `dump_abi` and `diff_abi`. A sample invocation looks as
follows:

    $ diff_abi --baseline abi1.xml --new abi2.xml --report report.out

The report created is tool specific, but generally lists ABI changes detected
that affect the Kernel's module interface. The files specified as `baseline`
and `new` are ABI representations collected with `dump_abi`. `diff_abi`
propagates the exit code of the underlying tool and therefore returns a
non-zero value in case the ABIs compared are incompatible.

Dealing with ABI breakages
--------------------------

As an example, the following patch introduces a very obvious ABI breakage:

    diff --git a/include/linux/mm_types.h b/include/linux/mm_types.h
    index 5ed8f6292a53..f2ecb34c7645 100644
    --- a/include/linux/mm_types.h
    +++ b/include/linux/mm_types.h
    @@ -339,6 +339,7 @@ struct core_state {
     struct kioctx_table;
     struct mm_struct {
        struct {
    +       int dummy;
            struct vm_area_struct *mmap;            /* list of VMAs */
            struct rb_root mm_rb;
            u64 vmacache_seqnum;                   /* per-thread vmacache */

Running `build_abi.sh` again with this patch applied, the tooling will exit
with a non-zero error code and will report an ABI difference similar to this:

    Leaf changes summary: 1 artifact changed
    Changed leaf types summary: 1 leaf type changed
    Removed/Changed/Added functions summary: 0 Removed, 0 Changed, 0 Added function
    Removed/Changed/Added variables summary: 0 Removed, 0 Changed, 0 Added variable

    'struct mm_struct at mm_types.h:372:1' changed:
      type size changed from 6848 to 6912 (in bits)
      there are data member changes:
    [...]
