#!/usr/bin/env python3
"""kmi_defines extract #define compile time constants from a Linux build.

The kmi_defines tool is used to examine the output of a Linux build
and extract from it C #define statements that define compile time
constant expressions for the purpose of tracking them as part of the
KMI (Kernel Module Interface) so that changes to their values can be
prevented so as to ensure a constant KMI for kernel modules for the
AOSP GKI Linux kernel project.

This code is python3 only, it does not require any from __future__
imports.  This is a standalone program, it is not meant to be used as
a module by other programs.

This program runs under the multiprocessing module.  Work done within
a multiprocessing.Pool does not perform error logging or affects any
state other than the value that it computes and returns via the function
mapped through the pool's map() function.  The reason that no external
state is affected (for example error loggiing) is to avoid to have to
even think about what concurrent updates would cause to shuch a facility.
"""

import logging
import multiprocessing
import os
import pathlib
import re
import subprocess
import sys
from typing import List, Tuple, Iterator, Iterable
from typing import Set  # pytype needs this, pylint: disable=unused-import

COMPILER = "clang"  # TODO(pantin): should be determined at run-time
PROGRAM = os.path.basename(sys.argv[0])


class StopError(Exception):
    """Exception raised through a call to stop()."""


# def stop(*args: Tuple[str]) -> None:
def stop(*args: str) -> None:
    """Raise an exception to stop the current work with *args message.

    This program is a muli-process program.  Errors that occur while doing
    the work assigned to a process (through the multiprocessing.Pool used
    by work_on_all_kernel_components()) causes that work to be stopped, the
    exception is caught by info_make() and turned into an InfoError object
    which is aggregated with all the other objects produced by the multi-
    processed work, which otherwise consists of objects derived from
    InfoKcomp.
    """
    raise StopError(" ".join([*args]))


def printerr(*args) -> None:
    """Similar to print(), but print to stderr."""
    print(*args, file=sys.stderr)


def usage() -> None:
    """Print the usage of an usage error."""
    printerr("usage:", PROGRAM, "[vmlinux.o | module.ko]")


def readfile(name: str) -> str:
    """Open a file and return its contents in a string as its value."""
    try:
        with open(name) as file:
            return file.read()
    except OSError as os_error:
        stop("could not read contents of:", name, "original OSError:",
             *os_error.args)


def file_must_exist(file: str) -> None:
    """If file is invalid print an error and stop()."""
    if not os.path.exists(file):
        stop("file does not exist:", file)
    if not os.path.isfile(file):
        stop("file is not a regular file:", file)


def find(pattern: str) -> Iterator[pathlib.Path]:
    """Enumerate recursively all files whose name match pattern."""
    return pathlib.Path().rglob(pattern)


def makefile_depends_split(depends: str) -> List[str]:
    """Split a makefile depends specification.

    The name of the dependent is followed by ":" its dependencies follow
    the ":".  There could be spaces around the ":".  Line continuation
    characters, i.e. "\" are consumed by the regular expression that
    splits the specification.
    """
    return re.split(r"[:\s\\]+", re.sub(r"[\s\\]*\Z", "", depends))


def makefile_depends_get_dependencies(depends: str) -> List[str]:
    """Return list with the dependencies of a makefile target."""
    return makefile_depends_split(depends)[1:]


def makefile_assignment_split(assignment: str) -> Tuple[str, str]:
    """Split left:=right into a tuple with the left and right parts.

    Spaces around the := are also removed.
    """
    result = re.split(r"\s*:=\s*", assignment, maxsplit=1)
    if len(result) != 2:
        stop("expected: 'left<optional_spaces>:=<optional_spaces>right' in:",
             assignment)
    return result[0], result[1]  # left, right


def makefile_assignment_left(assignment: str) -> str:
    """Return the left part of an := makefile assignment."""
    left, _ = makefile_assignment_split(assignment)
    return left


def makefile_assignment_right(assignment: str) -> str:
    """Return the right part of an := makefile assignment."""
    _, right = makefile_assignment_split(assignment)
    return right


def extract_c_src(obj: str, dependencies: List[str]) -> Tuple[str, List[str]]:
    """Return the C source file and the dependencies for the obj (.o) file.

    Excludes the source code file from the list of dependencies.  If the
    source was not a C file, returns "", [].
    """
    if not dependencies:
        stop("empty dependencies for:", obj)
    src = dependencies[0]
    if not src.endswith(".c"):
        return "", []
    return src, dependencies[1:]


def lines_to_list(lines: str) -> List[str]:
    """Split a string into a list of lines.

    Heading and trailing newlines are removed to ensure that empty list
    items are not present at the start or the end of the list.  Note that
    space characters are not considered when removing the heading and
    trailing newlines in case the space characters are relevant to the
    caller.

    Splitting an empty string into a list of lines ends up with a
    degenerate list with one entry, an empty string, e.g.:
        >>> print(re.split(r"\n+", ""))
        ['']
        >>>
    In that case this function returns an empty list, because there are
    no lines in the empty string, so an empty list of lines is less
    confusing to its callers.
    """
    values = re.split(r"\n+", re.sub(r"(\A\n*|\n*\Z)", "", lines))
    if values == [""]:
        return []
    return values


def lines_get_first_line(lines: str) -> str:
    """Return the first line in lines, ignoring all leading '\n' characters.

    E.g. return the first line with something in it, this is the same as:
        lines_to_list(lines)[0]
    but more efficient because it uses maxplit=1, and the number of lines
    involved are arnoud 1000, forming a 1000 line list to just extract the
    first one is wasteful.
    """
    return re.split(r"\n+", re.sub(r"(\A\n*|\n*\Z)", "", lines), maxsplit=1)[0]


def spaces_to_list(string: str) -> List[str]:
    """Split a whitespace separated string into a list.

    Leading and trailing whitespace is removed to ensure that empty itemts
    don't occur at the end or the start of the list.
    """
    #   The code below seems to work, keeping this in case of surprises later:
    #       return re.split(r"\s+", re.sub(r"(\A\s+|\s+\Z)", "", string))
    return string.split()


def shell_line_to_o_files_list(line: str) -> List[str]:
    """Return a list of .o files in the files list."""
    return [entry for entry in spaces_to_list(line) if entry.endswith(".o")]


class Kmod:
    """A kernel module, i.e. a *.ko file.

    Note that all the code in Kmod could live inside of InfoKmod, and the
    Kmod class could then be removed.  Purposely, for encapsulation, Kmod
    is kept separate so that understanding InfoKmod is easier and its
    relationship to Info, InfoKcomp, etc.  Furthermore, folding Kmod into
    InfoKmod would more tighly couple it with InfoKcomp and Info.
    """
    def __init__(self, kofile: str) -> None:
        """Contruct a Kmod object."""
        #   An example argument is used below, assuming kofile is:
        #       possibly/empty/dirs/dummy_hcd.ko
        #
        #   Meant to refer to this module, shown here relative to the top of
        #   the build directory:
        #       drivers/usb/gadget/udc/dummy_hcd.ko
        #   the values assigned to the members are shown in the comments below.

        self.file = os.path.realpath(kofile)  # /abs/dirs/dummy_hcd.ko
        self.base = os.path.basename(self.file)  # dummy_hcd.ko

        #   Ensure that:
        #      self.directory + self.base == self.file
        #   by including in self.directory a trailing slash

        self.directory = os.path.dirname(self.file) + "/"  # /abs/dirs/

        self.cmd_file = self.directory + "." + self.base + ".cmd"
        self.cmd_text = readfile(self.cmd_file)

        #   Some builds append a '; true' to the .dummy_hcd.ko.cmd, remove it

        self.cmd_text = re.sub(r";[\s]*true[\s]*$", "", self.cmd_text)

        #   The modules .dummy_hcd.ko.cmd file contains a makefile snippet,
        #   for example:
        #       cmd_drivers/usb/gadget/udc/dummy_hcd.ko := ld.lld -r ...
        #
        #   Split the string prior to the spaces followed by ":=", and get
        #   the first element of the resulting list.  If the string was not
        #   split (because it did not contain a ":=" then the input string
        #   is returned as the only element of the list.

        left = makefile_assignment_left(self.cmd_text)
        self.rel_file = re.sub(r"^cmd_", "", left)
        if self.rel_file == left:
            stop("expected: 'cmd_' at start of content of:", self.cmd_file)

        base = os.path.basename(self.rel_file)
        if base != self.base:
            stop("module name mismatch:", base, "vs", self.base)

        #   If self.rel_dir is not empty, ensure that:
        #      self.rel_dir + self.base == self.rel_file
        #   by including in self.rel_dir a trailing slash

        self.rel_dir = os.path.dirname(self.rel_file)
        if self.rel_dir:
            self.rel_dir += "/"

        #   The final step in the build of kernel modules is based on two .o
        #   files, one with the module name followed by .o and another followed
        #   by .mod.o
        #
        #   The following test verifies that assumption, in case a module is
        #   built differently in the future.
        #
        #   Even when there are multiple source files, the .o files that result
        #   from compiling them are all linked into a single .o file through an
        #   intermediate link step, that .o files is named:
        #       self.rel_dir + kofile_name + ".o"

        kofile_name = self.get_kofile_name()
        objs = shell_line_to_o_files_list(self.cmd_text)
        objs.sort()  # sorts the list in place
        expected = [  # sorted, i.e.: .mod.o < .o
            self.rel_dir + kofile_name + ".mod.o",
            self.rel_dir + kofile_name + ".o"
        ]
        if objs != expected:
            stop("unexpected .o files in:", self.cmd_file)

    def get_kofile_name(self) -> str:
        """Return the name part of the kofile without its .ko extension.

        For example, for "dummy_hcd.ko" return "dummy_hcd"
        """
        kofile_name, _ = os.path.splitext(self.base)
        return kofile_name

    def get_build_dir(self) -> str:
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.
        """
        #   index = self.file.rfind(self.rel_file)
        #   if index >= 0 and index + len(self.rel_file) != len(self.file):
        #       stop("could not find:", self.rel_file, "at end of:", self.file)
        if not self.file.endswith(self.rel_file):
            stop("could not find:", self.rel_file, "at end of:", self.file)
        index = len(self.file) - len(self.rel_file)
        build_dir = self.file[0:index]
        return build_dir

    def get_files_o(self, build_dir: str) -> List[str]:
        """Return a list object files that used to link the kernel module."""
        #   If the ocmd file has a more than one line in it, its because the
        #   module is made of a single source file and the ocmd file has the
        #   compilation rule and dependecies to build it.  If it has a single
        #   line single line it is because it builds the .o file by linking
        #   multiple .o files.

        kofile_name = self.get_kofile_name()
        ocmd = build_dir + self.rel_dir + "." + kofile_name + ".o.cmd"
        ocmd_content = readfile(ocmd)

        olines = lines_to_list(ocmd_content)
        if len(olines) > 1:  # module made from a single .o file
            return [build_dir + self.rel_dir + kofile_name + ".o"]

        #   Multiple .o files in the module

        ldline = makefile_assignment_right(olines[0])
        olist = []
        for obj in shell_line_to_o_files_list(ldline):
            olist.append(os.path.realpath(build_dir + obj))
        return olist


class Kernel:
    """The Linux kernel component itself, i.e. vmlinux.o.

    Note that all the code in Kernel could live inside of InfoKernel, and
    the Kernel class could then be removed.  Purposely, for encapsulation,
    Kernel is kept separate so that understanding InfoKernel is easier and
    its relationship to Info, InfoKcomp, etc.  Furthermore, folding Kernel
    into InfoKernel would more tighly couple it with InfoKcomp and Info.
    """
    def __init__(self, kernel: str) -> None:
        """Contruct a Kernel object."""
        self.kernel = os.path.realpath(kernel)
        self.build_dir = os.path.dirname(self.kernel) + "/"
        libs = self.build_dir + "vmlinux.libs"
        objs = self.build_dir + "vmlinux.objs"
        file_must_exist(libs)
        file_must_exist(objs)
        contents = readfile(libs)
        aolist = spaces_to_list(contents)
        contents = readfile(objs)
        aolist += spaces_to_list(contents)
        self.list_a_o = []
        for file in aolist:
            if file[0] != "/":
                file = self.build_dir + file
            self.list_a_o.append(file)

    def get_build_dir(self) -> str:
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.
        """
        return self.build_dir

    def get_files_o(self, build_dir: str) -> List[str]:
        """Return a list object files that where used to link the kernel."""
        olist = []
        for file in self.list_a_o:
            if file.endswith(".o"):
                if file[0] != "/":
                    file = build_dir + file
                olist.append(os.path.realpath(file))
                continue

            if not file.endswith(".a"):
                stop("unknown file type", file)

            try:
                #   This argument does not always work: check=False
                #   neither that nor: check=True prevents an exception from
                #   being raised if "ar" can not be found
                completion = subprocess.run(["ar", "t", file],
                                            capture_output=True,
                                            text=True)
                if completion.returncode != 0:
                    stop("ar failed for: ar t " + file)
                objs = lines_to_list(completion.stdout)
            except OSError as os_error:
                stop("failure executing: ar t", file, "original OSError:",
                     *os_error.args)

            for obj in objs:
                if obj[0] != "/":
                    obj = build_dir + obj
                olist.append(os.path.realpath(obj))

        return olist


class Target:  # pylint: disable=too-few-public-methods
    """Target of build and the information used to build it."""
    def __init__(self, obj: str, src: str, ccline: str,
                 dependencies: List[str]) -> None:
        self.obj = obj
        self.src = src
        self.ccline = ccline
        self.dependencies = dependencies


class Info:
    """Base class forclasses: InfoError, InfoKmod, and InfoKernel."""
    def __init__(self) -> None:
        """Contruct an info."""


class InfoError(Info):
    """A failed attempt to create either and InfoKmod or an InfoKernel.

    When that creation fails an StopError is raised by stop().
    The StopError contains it *args member the stop() message.
    """
    def __init__(self, filename: str, message: str) -> None:
        """Construct an InforError with an error message string."""
        super(InfoError, self).__init__()
        self.filename = filename
        self.message = message

    def get_error(self) -> str:
        """There was an error, return the error message."""
        return self.message


class InfoKcomp(Info):
    """Information about a kernel component, either vmlinux.o or a *.ko file.

    Inspect a Linux kernel module (a *.ko file) or the Linux kernel to
    determine what was used to build it: object filess, source files, header
    files, and other information that is produced as a by-product of its build.
    """
    def __init__(self) -> None:
        """Contruct an InfoKcomp object."""
        super(InfoKcomp, self).__init__()
        self.build_dir = self.get_build_dir()
        self.source_dir = self.get_source_dir()
        self.files_o = self.get_files_o()
        self.init_build_data()

    def init_build_data(self) -> None:
        """Initialize the build data.

        Steps:
        - remove from self.files_o the files not built by the compiler;
        - for each file in self.files_o set the corresponding .o.d.keep
          in self.files_o_d_keep;
        - set in set in self.dependencies the sorted unique list of headers
          included by the files in self.files.o;
        - save the compilation lines in the self.compile_lines dictionary.
        """
        self.files_o.sort()
        self.targets = []

        #   using a set because there is no unique flag to list.sort()
        deps = set()

        for obj in self.files_o:
            file_must_exist(obj)
            dot_obj = os.path.dirname(obj) + "/." + os.path.basename(obj)
            cmd = dot_obj + ".cmd"
            content = readfile(cmd)

            line = lines_get_first_line(content)
            ccline = makefile_assignment_right(line)
            if spaces_to_list(ccline)[0] != COMPILER:
                continue

            odkeep = dot_obj + ".d.keep"
            file_must_exist(odkeep)

            content = readfile(odkeep)
            src, dependendencies = extract_c_src(
                obj, makefile_depends_get_dependencies(content))
            if not src:
                continue
            file_must_exist(src)

            depends = []
            for dep in dependendencies:
                if dep[0] != "/":
                    dep = self.build_dir + dep
                dep = os.path.realpath(dep)
                depends.append(dep)
                deps.add(dep)

            if src[0] != "/":
                src = self.build_dir + self.source_dir
            src = os.path.realpath(src)

            self.targets.append(Target(obj, src, ccline, depends))

        non_h_files = []
        for dep in list(deps):
            file_must_exist(dep)
            if not dep.endswith(".h"):
                non_h_files.append(dep)
        for dep in non_h_files:
            deps.remove(dep)
        self.dependencies = deps

    def get_build_dir(self) -> str:  # pylint: disable=no-self-use
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.
        This member function is meant to be overriden by derived classes.
        """
        stop("InfoKcomp.get_build_dir() called, its meant to be overriden")
        return ""

    def get_source_dir(self) -> str:
        """Return the top level Linux kernel source directory."""
        source = self.build_dir + "source"
        if not os.path.islink(source):
            stop("could not find source symlink:", source)

        if not os.path.isdir(source):
            stop("source symlink not a directory:", source)

        source_dir = os.path.realpath(source) + "/"
        if not os.path.isdir(source_dir):
            stop("source directory not a directory:", source_dir)

        return source_dir

    def get_files_o(self) -> List[str]:  # pylint: disable=no-self-use
        """Return a list of object files used to link the kernel component.

        This member function is meant to be overriden by derived classes.
        """
        stop("InfoKcomp.get_files_o() called, its meant to be overriden")
        return []


class InfoKmod(InfoKcomp):
    """Information about a Linux kernel module, i.e. a *.ko file."""
    def __init__(self, kofile: str) -> None:
        """Contruct an InfoKmod object."""
        self.kmod = Kmod(kofile)
        super(InfoKmod, self).__init__()

    def get_build_dir(self) -> str:
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.
        """
        return self.kmod.get_build_dir()

    def get_files_o(self) -> List[str]:
        """Return a list of object files used to link the kernel module."""
        return self.kmod.get_files_o(self.build_dir)


class InfoKernel(InfoKcomp):
    """Information about the Linux kernel, i.e. vmlinux.o."""
    def __init__(self, kernel_file: str) -> None:
        """Contruct an InfoKernel object."""
        self.kernel = Kernel(kernel_file)
        super(InfoKernel, self).__init__()

    def get_build_dir(self) -> str:
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.
        """
        return self.kernel.get_build_dir()

    def get_files_o(self) -> List[str]:
        """Return a list of object files used to link the kernel module."""
        return self.kernel.get_files_o(self.build_dir)


def info_make(filename: str) -> Info:
    """Make an InfoKmod or an InfoKernel object for file and return it."""
    try:
        if filename.endswith("vmlinux.o"):
            info = InfoKernel(filename)
        else:
            info = InfoKmod(filename)
    except StopError as stop_error:
        info = InfoError(filename, *stop_error.args)
    return info


def info_show(info: Info):
    """Show errors if info is an InfoError."""
    if isinstance(info, InfoError):
        err = info.get_error()
        logging.error(info.filename + err)
        return


def all_ko_and_vmlinux() -> Iterable[str]:
    """Generator that yields vmlinux.o and all the *.ko files."""
    yield "vmlinux.o"  # yield vmlinux.o so its worked on first
    for kofile in find("*.ko"):
        yield str(kofile)


def work_on_all_kernel_components() -> List[Info]:
    """Return a list of Info objects, one for each .ko file."""
    with multiprocessing.Pool(os.cpu_count()) as pool:
        infos = pool.map(info_make, all_ko_and_vmlinux())
    return infos


def work_on_whole_build() -> int:
    """Work on the whole build to extract the #define constants."""
    infos = work_on_all_kernel_components()
    all_kmod_h_set = set()
    kernel_h_set = set()
    for info in infos:
        info_show(info)
        if isinstance(info, InfoKernel):
            kernel_h_set = info.dependencies
        elif isinstance(info, InfoKmod):
            all_kmod_h_set |= info.dependencies

    headers = kernel_h_set & all_kmod_h_set
    hlist = list(headers)
    for dep in hlist:
        print(dep)
    return 0


def main() -> int:
    """Extract info from an individual file (vmlinux or a kernel module).

    Or if invoked with no arguments extract the compile time constants
    from #define declarations relevant to the KMI.
    """

    if len(sys.argv) > 2:
        usage()
        return 1

    file = "vmlinux.o"
    if len(sys.argv) == 2:
        file = sys.argv[1]
    if not os.path.exists(file) or not os.path.isfile(file):
        printerr(PROGRAM + ": error: invalid file: ", file)
        usage()
        return 1

    if len(sys.argv) == 1:
        return work_on_whole_build()

    info = info_make(file)
    info_show(info)
    if isinstance(info, InfoError):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
