#!/usr/bin/python3
"""
    kmi_defines extract #define compile time constants from a Linux build.

    The kmi_defines tool is used to examine the output of a Linux build
    and extract from it C #define statements that define compile time
    constant expressions for the purpose of tracking them as part of the
    KMI (Kernel Module Interface) so that changes to their values can be
    prevented so as to ensure a constant KMI for kernel modules for the
    AOSP GKI Linux kernel project.
"""

#   This code is python3 only, it does not require any from __future__
#   imports.  This is a standalone program, it is not meant to be used as
#   a module by other programs.
#
#   A note about the use of pytype, the type comments when variables are
#   first set, e.g.:
#       var = foo()  # type: str
#   significantly clutter the code. The ought to be a way to specify a
#   default type for all variables whose types is not specified in a comment.

from typing import List, Tuple, Iterator, Iterable
from typing import Set  # used for typeing, pylint: disable=unused-import
import re
import os
from os.path import exists, isdir, isfile, islink, basename, dirname
import sys
import pathlib
import subprocess
import multiprocessing

DEBUG = False  # type: bool
COMPILER = "clang"  # type: str
PROGRAM = os.path.basename(sys.argv[0])  # type: str


class ExitError(Exception):
    """ Exception raised when an unexpected condition is detected """
    def __init__(self, message: str) -> None:
        super(ExitError, self).__init__()
        self.message = message  # type: str

    def get_message(self) -> str:
        """ return the error message stored in the exception object """
        return self.message


def stop(*args: str) -> None:
    """
        The args, which eventually make it to print(), are the exception value.
        Raise an ExitError() exception to abort processing, this is needed
        because calling exit() from multiprocessing code ends up in a deadlock,
        seems natural enough to use this to deal with that issue.  This program
        does not use raise exceptions purposely otherwise
    """
    message = ""  # type: str
    for arg in args:  # type: str
        if not message:
            message = arg
        else:
            message += " " + arg
    raise ExitError(message)


def printerr(*args) -> None:
    """ Similar to print(), but print to stderr """
    print(*args, file=sys.stderr)


def usage() -> None:
    """ Print the usage of an usage error """
    printerr("usage:", PROGRAM, "[vmlinux.o | module.ko]")


def error(*args) -> None:
    """
        Similar to print(), but print to stderr and prefix the output with
        the program name and an "error:" label
    """
    printerr(PROGRAM + ": error:", *args)


def warning(*args) -> None:
    """
        Similar to print(), but print to stderr and prefix the output with
        the program name and a "warning:" label
    """
    printerr(PROGRAM + ": warning:", *args)


def todo(*args) -> None:
    """ Write error message to indicate that code has not been implemented """
    stop("todo: missing code:", *args)


def invalid_file(file: str) -> str:
    """
        Determine if file exists and if it is a regular file, if so an empty
        string is returned, otherwise the reason for the file's invalidity
        is returned in the string value
    """
    if not exists(file):
        return "file does not exist:"
    if not isfile(file):
        return "file is not a regular file:"
    return ""


def chdir(directory: str) -> bool:
    """ Change directory and return whether the operation succeeded """
    try:
        os.chdir(directory)
        return True
    except OSError:
        return False


def readfile(name: str) -> str:
    """
        Open a file and return its contents in a string as its value.
        Aborts execution of the operation failed.
    """
    try:
        with open(name) as file:  # closed by the with context manager
            return file.read()
    except OSError:
        stop("could not read contents of:", name)


def file_must_exist(file: str) -> None:
    """ If file is invalid print an error and exit """
    invalid = invalid_file(file)  # type: str
    if invalid:
        stop(invalid, file)


def find(pattern: str) -> Iterator[pathlib.Path]:
    """
        Enumerate recursively from the current directory all files whose
        name patch pattern
    """
    return pathlib.Path().rglob(pattern)


def makefile_depends_split(depends: str) -> List[str]:
    """
        Split a makefile depends specification.  The name of the dependent
        is followed by ":" its dependencies follow the ":".  There could be
        spaces around the ":".  Line continuation characters, i.e. "\" are
        consumed by the regular expression that splits the specification.
    """
    return re.split(r"[:\s\\]+", re.sub(r"[\s\\]*\Z", "", depends))


def makefile_depends_get_dependencies(depends: str) -> List[str]:
    """
        Return a possibly empty list with the dependencies of a makefile target
    """
    return makefile_depends_split(depends)[1:]


def makefile_assignment_split(assignment: str) -> Tuple[str, str]:
    """
        Split: left<optional_spaces>:=<optional_spaces>right into a tuple
        with the left and right parts.
        Aborts execution if there was no assignment to split.
    """
    result = re.split(r"\s*:=\s*", assignment, maxsplit=1)  # type: List[str]
    if len(result) != 2:
        stop("expected: 'left<optional_spaces>:=<optional_spaces>right' in:",
             assignment)
    return result[0], result[1]  # left, right


def makefile_assignment_left(assignment: str) -> str:
    """ Return the left part of an := makefile assignment """
    left, right = makefile_assignment_split(
        assignment)  # type: Tuple[str, str]
    del right
    return left


def makefile_assignment_right(assignment: str) -> str:
    """ Return the right part of an := makefile assignment """
    left, right = makefile_assignment_split(assignment)
    del left
    return right


def extract_c_src(obj: str, dependencies: List[str]) -> Tuple[str, List[str]]:
    """
        Return the source file and the dependencies for the obj (.o) file
        after excluding the source code file from the list of dependencies.
        If the source was not a .c file, returns "", [].
    """
    if not dependencies:
        stop("empty dependencies for:", obj)
    src = dependencies[0]  # type: str
    if not ends_in(src, ".c"):
        return "", []
    return src, dependencies[1:]


def lines_to_list(lines: str) -> List[str]:
    """
        Split a string into a list of lines, heading and trailing newlines
        are removed to ensure that empty list items are not present at the
        start or the end of the list.  Note that space characters are not
        considered when removing the heading and trailing newlines in case
        the space characters are relevant to the caller.

        Splitting an empty string into a list of lines ends up with a
        degenerate list with one entry, an empty string, e.g.:
            >>> print(re.split(r"\n+", ""))
            ['']
            >>>
        In that case this function returns an empty list, because there are
        no lines in the empty string, so an empty list of lines is less
        confusing to its callers.
    """
    values = re.split(r"\n+", re.sub(r"(\A\n*|\n*\Z)", "",
                                     lines))  # type: List[str]
    if values == [""]:
        return []
    return values


def lines_get_first_line(lines: str) -> str:
    """
        Return the first line in lines, ignoring all leading '\n' characters.
        E.g. return the first line with something in it.  This is the same
        as using:
            lines_to_list(lines)[0]
        but more efficient because it uses maxplit=1
    """
    return re.split(r"\n+", re.sub(r"(\A\n*|\n*\Z)", "", lines), maxsplit=1)[0]


def spaces_to_list(string: str) -> List[str]:
    """
        Split a string into a list, items in the list are separated by
        whitespace characters.  Leading and trailing whitespace is removed
        to ensure that empty itemts don't occur at the end or the start of
        the list.
    """
    return re.split(r"\s+", re.sub(r"(\A\s+|\s+\Z)", "", string))


def ends_in(value: str, end: str) -> bool:
    """ Returns True if value has end at its end """
    index = value.rfind(end)  # type: int
    return index >= 0 and index + len(end) == len(value)


def shell_line_to_o_files_list(line: str) -> List[str]:
    """ Return a list of .o files in the files list """
    result = []  # type: List[str]
    for entry in spaces_to_list(line):  # type: str
        if ends_in(entry, ".o"):
            result.append(entry)
    return result


class Kmod:
    """
        A kernel module, i.e. a *.ko file. Note that all the code in Kmod
        could live inside of InfoKmod, and the Kmod class could then be
        removed.  Purposely, for encapsulation, Kmod is kept separate so
        that understanding InfoKmod is easier and its relationship to Info,
        InfoKcomp, etc.  Furthermore, folding Kmod into InfoKmod would more
        tighly couple it with InfoKcomp and Info.  This is best kept separate.
    """
    def print(self) -> None:
        """ Print the information stored in the Kmod object. """

        #   initialized by init_basic_vars()

        print("file           =", self.file)
        print("base           =", self.base)
        print("directory      =", self.directory)
        print()

        #   initialized by init_cmd_vars()

        print("cmd_file       =", self.cmd_file)
        print("cmd_text       =", self.cmd_text)
        print()

        #   initialized by init_kofilerel_vars():

        print("rel_file       =", self.rel_file)
        print("rel_dir        =", self.rel_dir)
        print()

    def init_kofile_vars(self, kofile: str) -> None:
        """
            Initialize self.file, self.base and self.directory
        """
        #   For this kofile argument:
        #       possibly/empty/dirs/dummy_hcd.ko
        #
        #   Meant to refer to this module, shown here relative to the top of
        #   the build directory:
        #       drivers/usb/gadget/udc/dummy_hcd.ko
        #   the values assigned to the members is shown in the comments below.

        self.file = os.path.realpath(kofile)  # /absdir/dummy_hcd.ko type: str
        self.base = basename(self.file)  # dummy_hcd.ko type: str

        #   Ensure that:
        #      self.directory + self.base == self.file
        #   by including in self.directory a trailing slash

        self.directory = dirname(self.file) + "/"  # /absdir/ type: str

    def init_cmd_vars(self) -> None:
        """
            Initialize self.cmd_file, and self.cmd_text
        """
        self.cmd_file = self.directory + "." + self.base + ".cmd"  # type: str
        self.cmd_text = readfile(self.cmd_file)  # type: str

        #   Some builds append a '; true' to the .dummy_hcd.ko.cmd, remove it

        self.cmd_text = re.sub(r";[\s]*true[\s]*$", "",
                               self.cmd_text)  # type: str

    def init_kofilerel_vars(self) -> None:
        """
            Initialize self.rel_file and self.rel_dir
        """
        #   The modules .dummy_hcd.ko.cmd file contains a makefile snippet,
        #   for example:
        #       cmd_drivers/usb/gadget/udc/dummy_hcd.ko := ld.lld -r ...
        #
        #   Split the string prior to the spaces followed by ":=", and get
        #   the first element of the resulting list.  If the string was not
        #   split (because it did not contain a ":=" then the input string
        #   is returned as the only element of the list.

        left = makefile_assignment_left(self.cmd_text)  # type: str
        self.rel_file = re.sub(r"^cmd_", "", left)  # type: str
        if self.rel_file == left:
            stop("expected: 'cmd_' at start of content of:", self.cmd_file)

        base = basename(self.rel_file)  # type: str
        if base != self.base:
            stop("module name mismatch:", base, "vs", self.base)

        #   If self.rel_dir is not empty, ensure that:
        #      self.rel_dir + self.base == self.rel_file
        #   by including in self.rel_dir a trailing slash

        self.rel_dir = dirname(self.rel_file)  # type: str
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

        kofile_name = self.get_kofile_name()  # type: str
        objs = shell_line_to_o_files_list(self.cmd_text)  # type: List[str]
        objs.sort()  # sorts the list in place
        expected = [  # sorted, i.e.: .mod.o < .o; type: List[str]
            self.rel_dir + kofile_name + ".mod.o",
            self.rel_dir + kofile_name + ".o"
        ]
        if objs != expected:
            stop("unexpected .o files in:", self.cmd_file)

    def get_kofile_name(self) -> str:
        """
            return the name part of the kofile without its .ko extension
            e.g. for "dummy_hcd.ko" return "dummy_hcd"
        """
        kofile_name, ext = os.path.splitext(self.base)  # type: Tuple[str, str]
        del ext  # to make pyliny3 happy
        return kofile_name

    def get_build_dir(self) -> str:
        """
            Return the top level build directory, i.e. the directory where
            the output of the Linux build is stored
        """
        index = self.file.rfind(self.rel_file)  # type: int
        if index >= 0 and index + len(self.rel_file) != len(self.file):
            stop("could not find:", self.rel_file, "at end of:", self.file)

        build_dir = self.file[0:index]  # type: str
        return build_dir

    def get_files_o(self, build_dir: str) -> List[str]:
        """
            Return a list with of object files that where used to link the
            kernel module.
        """
        #   If the ocmd file has a more than one line in it, its because the
        #   module is made of a single source file and the ocmd file has the
        #   compilation rule and dependecies to build it.  If it has a single
        #   line single line it is because it builds the .o file by linking
        #   multiple .o files.

        kofile_name = self.get_kofile_name()  # type: str
        ocmd = (build_dir + self.rel_dir + "." + kofile_name + ".o.cmd"
                )  # type: str
        ocmd_content = readfile(ocmd)  # type: str

        olines = lines_to_list(ocmd_content)  # type: List[str]
        if len(olines) > 1:  # module made from a single .o file
            return [build_dir + self.rel_dir + kofile_name + ".o"]

        #   Multiple .o files in the module

        ldline = makefile_assignment_right(olines[0])  # type: str
        olist = []
        for obj in shell_line_to_o_files_list(ldline):  # type: str
            olist.append(os.path.realpath(build_dir + obj))
        return olist

    def __init__(self, kofile: str) -> None:
        """ Contruct a Kmod object """
        self.init_kofile_vars(kofile)
        self.init_cmd_vars()
        self.init_kofilerel_vars()


class Kernel:
    """
        The Linux kernel component itself, i.e. vmlinux.o.  Note that all
        the code in Kernel could live inside of InfoKernel, and the Kernel
        class could then be removed.  Purposely, for encapsulation, Kernel
        is kept separate so that understanding InfoKernel is easier and its
        relationship to Info, InfoKcomp, etc.  Furthermore, folding Kernel
        into InfoKernel would more tighly couple it with InfoKcomp and Info.
        This is best kept separate.
    """
    def print(self) -> None:
        """ Print the information stored in the Kernel object. """
        print("file_a_o:")
        for file in self.list_a_o:  # type: str
            print(file)
        print()

    def get_build_dir(self) -> str:
        """
            Return the top level build directory, i.e. the directory where
            the output of the Linux build is stored
        """
        return self.build_dir

    def get_files_o(self, build_dir: str) -> List[str]:
        """
            Return a list with of object files that where used to link the
            kernel.
        """
        olist = []  # type: List[str]
        for file in self.list_a_o:  # type: str
            if ends_in(file, ".o"):
                if file[0] != "/":
                    file = build_dir + file  # type: str
                olist.append(os.path.realpath(file))
                continue

            if not ends_in(file, ".a"):
                stop("unknown file type", file)

            try:
                #   This argument does not always work: check=False
                #   neither that nor: check=True prevents an exception from
                #   being raised if "ar" can not be found
                completion = subprocess.run(
                    ["ar", "t", file], capture_output=True,
                    text=True)  # type: subprocess.CompletedProcess
                if completion.returncode != 0:
                    stop("ar failed for: ar t " + file)
                objs = lines_to_list(completion.stdout)  # type: List[str]
            except OSError:
                stop("failure executing: ar t " + file)

            for obj in objs:  # type: str
                if obj[0] != "/":
                    obj = build_dir + obj  # type: str
                olist.append(os.path.realpath(obj))

        return olist

    def __init__(self, kernel: str) -> None:
        """ Contruct a Kernel object """
        self.kernel = os.path.realpath(kernel)  # type: str
        self.build_dir = dirname(self.kernel) + "/"  # type: str
        libs = self.build_dir + "vmlinux.libs"  # type: str
        objs = self.build_dir + "vmlinux.objs"  # type: str
        file_must_exist(libs)
        file_must_exist(objs)
        contents = readfile(libs)  # type: str
        aolist = spaces_to_list(contents)  # type: List[str]
        contents = readfile(objs)  # type: str
        aolist += spaces_to_list(contents)
        self.list_a_o = []  # type: List[str]
        for file in aolist:  # type: str
            if file[0] != "/":
                file = self.build_dir + file  # type: str
            self.list_a_o.append(file)


class Target:  # pylint: disable=too-few-public-methods
    """ Target of build and the information used to build it """
    def print(self) -> None:
        """ Print its members """
        print("obj            =", self.obj)
        print("src            =", self.src)
        print("ccline         =", self.ccline)

        print("dependencies:")
        for dep in self.dependencies:  # type: str
            print(dep)
        print()

    def __init__(self, obj: str, src: str, ccline: str,
                 dependencies: List[str]) -> None:
        self.obj = obj  # type: str
        self.src = src  # type: str
        self.ccline = ccline  # type: str
        self.dependencies = dependencies  # type: List[str]


class Info:
    """
        Base class for all the kinds of Info derived classes: InfoError,
        InfoKmod, and InfoKernel
    """
    def print(self) -> None:
        """ pytype is unhappy without this """
    def get_info_error(self) -> None:  # pylint: disable=no-self-use
        """
            Meant to be overriden by InfoError to go from Info to InfoError,
            all descendants of Info, other than InfoError, inherit this one
        """
        return None

    def __init__(self) -> None:
        """ Contruct an info """


class InfoError(Info):
    """
        An InfoError corresponds to a failed attempt to create some kind
        of Info, either InfoKmod or InfoKernel. When that creation fails
        an ExitError is raised by stop(). The ExitError contains the message
        that describes the error cause.
    """
    def get_info_error(self):
        return self

    def get_error(self) -> str:
        """ There was an error, return the error message """
        return self.message

    def __init__(self, filename: str, message: str) -> None:
        """ Construct an InforError with an error message string. """
        super(InfoError, self).__init__()
        self.filename = filename  # type: str
        self.message = message  # type: str


class InfoKcomp(Info):
    """
        Information about a kernel component, either vmlinux.o or a *.ko file.

        Inspect a Linux kernel module (a *.ko file) or the Linux kernel to
        determine what was used to build it: object filess, source files,
        header files, and other information that is produced as a by-product
        of its build.
    """
    def print(self) -> None:
        """
            Print the information stored in the InfoKcomp object.
        """

        #   initialized by __init__()

        print("build_dir      =", self.build_dir)
        print("source_dir     =", self.source_dir)
        print()

        #   initialized by init_build_data()

        print("files_o:")
        for obj in self.files_o:  # type: str
            print(obj)
        print()

        print("dependencies:")
        for dependency in list(self.dependencies):  # type: str
            print(dependency)
        print()

        print("targets:")
        for target in self.targets:  # type: Target
            target.print()
        print()

    def init_build_data(self) -> None:
        """
            Remove from self.files_o the files not built by the compiler;
            for each file in self.files_o set the corresponding .o.d.keep
            in self.files_o_d_keep; set in set in self.dependencies the sorted
            unique list of headers included by the files in self.files.o;
            save the compilation lines in the self.compile_lines dictionary.
        """
        self.files_o.sort()
        self.targets = []  # type: List[str]

        #   using a set because no unique flag to list.sort()
        deps = set()  # type: Set[str]

        for obj in self.files_o:  # type: str
            file_must_exist(obj)
            dot_obj = dirname(obj) + "/." + basename(obj)  # type: str
            cmd = dot_obj + ".cmd"  # type: str
            content = readfile(cmd)  # type: str

            line = lines_get_first_line(content)  # type: str
            ccline = makefile_assignment_right(line)  # type: str
            if spaces_to_list(ccline)[0] != COMPILER:
                continue

            odkeep = dot_obj + ".d.keep"  # type: str
            file_must_exist(odkeep)

            content = readfile(odkeep)  # type: str
            src, dependendencies = extract_c_src(
                obj, makefile_depends_get_dependencies(
                    content))  # type: Tuple[str, List[str]]
            if not src:
                continue
            file_must_exist(src)

            depends = []  # type: List[str]
            for dep in dependendencies:  # type: str
                if dep[0] != "/":
                    dep = self.build_dir + dep
                dep = os.path.realpath(dep)  # type: str
                depends.append(dep)
                deps.add(dep)

            if src[0] != "/":
                src = self.build_dir + self.source_dir  # type: str
            src = os.path.realpath(src)  # type: str

            self.targets.append(Target(obj, src, ccline, depends))

        non_h_files = []  # type: List[str]
        for dep in list(deps):  # type: List[str]
            file_must_exist(dep)
            if not ends_in(dep, ".h"):
                non_h_files.append(dep)
        for dep in non_h_files:  # type: List[str]
            deps.remove(dep)
        self.dependencies = deps  # type: Set[str]

    def get_build_dir(self) -> str:  # pylint: disable=no-self-use
        """
            Return the top level build directory, i.e. the directory where
            the output of the Linux build is stored.  This member function
            is meant to be overriden by derived classes.
        """
        stop("InfoKcomp.get_build_dir() called, its meant to be overriden")
        return ""

    def get_source_dir(self) -> str:
        """ Return the top level Linux kernel source directory """
        source = self.build_dir + "source"  # type: str
        if not islink(source):
            stop("could not find source symlink:", source)

        if not isdir(source):
            stop("source symlink not a directory:", source)

        source_dir = os.path.realpath(source) + "/"  # type: str
        if not isdir(source_dir):
            stop("source directory not a directory:", source_dir)

        return source_dir

    def get_files_o(self) -> List[str]:  # pylint: disable=no-self-use
        """
            Return a list with of object files that where used to link the
            kernel module.  This member function is meant to be overriden by
            derived classes.
        """
        stop("InfoKcomp.get_files_o() called, its meant to be overriden")
        return []

    def __init__(self) -> None:
        """ Contruct an InfoKcomp object """
        super(InfoKcomp, self).__init__()
        self.build_dir = self.get_build_dir()  # type: str
        self.source_dir = self.get_source_dir()  # type: str
        self.files_o = self.get_files_o()  # type: List[str]
        self.init_build_data()


class InfoKmod(InfoKcomp):
    """ Information about a Linux kernel module, i.e. a *.ko file. """
    def print(self) -> None:
        """ Print the information stored in the InfoKmod object. """
        self.kmod.print()
        super(InfoKmod, self).print()

    def get_build_dir(self) -> str:
        """
            Return the top level build directory, i.e. the directory where
            the output of the Linux build is stored.
        """
        return self.kmod.get_build_dir()

    def get_files_o(self) -> List[str]:
        """
            Return a list with of object files that where used to link the
            kernel module.
        """
        return self.kmod.get_files_o(self.build_dir)

    def __init__(self, kofile: str) -> None:
        """ Contruct an InfoKmod object """
        self.kmod = Kmod(kofile)  # type: Kmod
        super(InfoKmod, self).__init__()


class InfoKernel(InfoKcomp):
    """ Information about the Linux kernel, i.e. vmlinux.o """
    def print(self) -> None:
        """ Print the information stored in the InfoKernel object. """
        self.kernel.print()
        super(InfoKernel, self).print()

    def get_build_dir(self) -> str:
        """
            Return the top level build directory, i.e. the directory where
            the output of the Linux build is stored.
        """
        return self.kernel.get_build_dir()

    def get_files_o(self) -> List[str]:
        """
            Return a list with of object files that where used to link the
            kernel module.
        """
        return self.kernel.get_files_o(self.build_dir)

    def __init__(self, kernel_file: str) -> None:
        """ Contruct an InfoKernel object """
        self.kernel = Kernel(kernel_file)  # type: Kernel
        super(InfoKernel, self).__init__()


def info_make(filename: str) -> Info:
    """ Make an InfoKmod or an InfoKernel object for file and return it """
    try:
        if filename == "vmlinux.o":
            info = InfoKernel(filename)  # type: Info
        else:
            info = InfoKmod(filename)  # type: Info
    except ExitError as exit_error:
        info = InfoError(filename, exit_error.get_message())  # type: Info
    return info


def all_ko_and_vmlinux() -> Iterable[str]:
    """ Generator that yields vmlinux.o and all the *.ko files """
    yield "vmlinux.o"  # yield vmlinux.o so its worked on first
    for kofile in find("*.ko"):  # type: pathlib.Path
        yield str(kofile)


def work_on_all_ko() -> List[Info]:
    """ Return a list of Info objects, one for each .ko file """
    with multiprocessing.Pool(os.cpu_count()) as pool:
        infos = pool.map(info_make, all_ko_and_vmlinux())  # type: List[Info]
        # infos = pool.map(info_make, find("*.ko"))
    return infos


def work_on_whole_build() -> None:
    """
        Work on the whole build to produce extract the compile time constant
        #defines that are relevant to GKI
    """
    file = "vmlinux.o"  # type: str
    invalid = invalid_file(file)  # type: str
    if invalid:
        error(invalid, file)
        usage()
        exit(1)
    infos = work_on_all_ko()  # type: List[Info]
    all_kmod_h_set = set()  # type: Set[str]
    kernel_h_set = set()  # type: Set[str]
    for info in infos:  # type: Info
        info_error = info.get_info_error()  # type: InfoError
        if info_error:
            err = info_error.get_error()  # type: str
            sys.stdout.flush()
            printerr("-" * 60, "{")
            error(info_error.filename, err)
            printerr("}\n")
            sys.stderr.flush()
            continue
        if DEBUG:
            print("-" * 60, "{")
            info.print()
            print("}\n")
        if isinstance(info, InfoKernel):
            kernel_h_set = info.dependencies
        else:
            all_kmod_h_set |= info.dependencies
    headers = kernel_h_set & all_kmod_h_set  # type: Set[str]
    hlist = list(headers)  # type: List[src]
    for dep in hlist:  # type: str
        print(dep)
    exit(0)


def main() -> None:
    """
        Extract info from an individual file (vmlinux or a kernel module).
        Or if invoked with no arguments extract the compile time constants
        from #define declarations relevant to the KMI.
    """
    if len(sys.argv) == 1:
        work_on_whole_build()
        exit(0)

    if len(sys.argv) != 2:
        usage()
        exit(1)

    file = sys.argv[1]  # type: str
    invalid = invalid_file(file)  # type: str
    if invalid:
        error(invalid, file)
        usage()
        exit(1)

    if ends_in(file, "vmlinux.o"):
        info = InfoKernel(file)  # type: Info
    else:
        name, ext = os.path.splitext(file)  # type: Typle[str, str]
        del name
        if ext != ".ko":
            usage()
            exit(1)
        info = InfoKmod(file)  # type: Info
    if DEBUG:
        info.print()
    exit(0)


if __name__ == "__main__":
    main()
