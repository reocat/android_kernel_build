#!/usr/bin/env python3
#
# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# pylint: disable=too-many-lines
#
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

#   TODO(pantin): per Matthias review feedback: "drop the .py from the
#   filename after(!) the review has completed. As last action. Until
#   then we can have the syntax highlighting here in Gerrit."

import argparse
import collections
import logging
import multiprocessing
import os
import pathlib
import re
import subprocess
import shlex
import sys
from typing import List, Optional, NamedTuple, Set, TextIO

INDENT = 4  # number of spaces to indent for each depth level
COMPILER = "clang"  # TODO(pantin): should be determined at run-time
KMI_C = [
    '#include "kmi_enums.h"',
    '#include "kmi_union.h"',
    'int __kmi_defs(union __kmi_union *p) { return p->__kmi_dummy; }',
]

#   Dependency that is hidden by the transformation of the .o.d file into
#   the .o.cmd file as part of the Linux build environment.  This header is
#   purposely removed and replaced by fictitious set of empty header files
#   that were never part of the actual compilation of the .o files.  Those
#   fictitious empty files are generated under the build environment output
#   directory in this subdirectory:
#       include/config
#
#   This is the actual header file that was part of the compilation of every
#   .o file, the HIDDEN_DEP are added to the dependencies of every .o file.
#
#   It is important that this file be added because it is unknowable whether
#   the #defines in it were depended upon by a module to alter its behaviour
#   at compile time.  For example to pass some flags or not pass some flags
#   to a function.

HIDDEN_DEP = "include/generated/autoconf.h"

#   These headers are excluded, see README-kmi_defines.md

EXCLUDE = {
    "drivers/net/ethernet/chelsio/cxgb4/t4_pci_id_tbl.h",
    "include/linux/wimax/debug.h",
    "include/rdma/uverbs_named_ioctl.h",
    "include/trace/bpf_probe.h",
    "include/trace/perf.h",
    "include/trace/trace_events.h",
    "include/uapi/linux/patchkey.h",
    "net/netfilter/ipset/ip_set_hash_gen.h",
    "sound/pci/echoaudio/echoaudio.h",
    "sound/pci/echoaudio/echoaudio_dsp.h",
}


class StopError(Exception):
    """Exception raised to stop work when an unexpected error occurs."""


def dump(this) -> None:
    """Dump the data in this.

    This is for debugging purposes, it does not handle every type, only
    the types used by the underlying code are handled.  This will not be
    part of the final code, or if it is, it will be significantly enhanced
    or replaced by some other introspection mechanism to serialize data.
    """
    def dump_this(this, name: str, depth: int) -> None:
        """Dump the data in this."""
        if name:
            name += " = "
        if isinstance(this, str):
            indent = " " * (depth * INDENT)
            print(indent + name + this)
        elif isinstance(this, bool):
            indent = " " * (depth * INDENT)
            print(indent + name + str(this))
        elif isinstance(this, List):
            dump_list(this, name, depth)
        elif isinstance(this, Set):
            dump_set(this, name, depth)
        else:
            dump_object(this, name, depth)

    def dump_list(lst: List[str], name: str, depth: int) -> None:
        """Dump the data in lst."""
        indent = " " * (depth * INDENT)
        print(indent + name + "{")
        index = 0
        for entry in lst:
            dump_this(entry, f"[{index}]", depth + 1)
            index += 1
        print(indent + "}")

    def dump_set(aset: Set[str], name: str, depth: int) -> None:
        """Dump the data in aset."""
        lst = list(aset)
        lst.sort()
        dump_list(lst, name, depth)

    def dump_object(this, name: str, depth: int) -> None:
        """Dump the data in this."""
        indent = " " * (depth * INDENT)
        print(indent + name +
              re.sub(r"(^<class '__main__\.|'>$)", "", str(type(this))) + " {")
        for key, val in this.__dict__.items():
            dump_this(val, key, depth + 1)
        print(indent + "}")

    dump_this(this, "", 0)


def read_whole_file(name: str) -> str:
    """Open a file and return its contents in a string as its value."""
    with open(name) as file:
        return file.read()


def write_whole_file(name: str, lines: List[str]) -> None:
    """Create a file and write a list of strings, one on each line, into it."""
    with open(name, "w+") as file:
        if lines:
            file.write("\n".join(lines) + "\n")


def read_file(name: str) -> str:
    """Open a file and return its contents in a string as its value.

    Catch OSError exceptions and transform them into StopError exceptions.
    """
    try:
        return read_whole_file(name)
    except OSError as os_error:
        raise StopError("read_file() failed for: " + name + "\n"
                        "original OSError: " + str(os_error.args))


def write_file(name: str, lines: List[str]) -> None:
    """Create a file and write a list of strings, one on each line, into it.

    Catch OSError exceptions and transform them into StopError exceptions.
    """
    try:
        write_whole_file(name, lines)
    except OSError as os_error:
        raise StopError("write_file() failed for: " + name + "\n"
                        "original OSError: " + str(os_error.args))


def file_must_exist(file: str) -> None:
    """If file is invalid raise a StopError."""
    if not os.path.exists(file):
        raise StopError("file does not exist: " + file)
    if not os.path.isfile(file):
        raise StopError("file is not a regular file: " + file)


def remove_file(file: str) -> None:
    """Remove file if it exists."""
    if os.path.isfile(file):
        os.remove(file)


def remove_files(files: List[str]) -> None:
    """Remove files if they exist."""
    for file in files:
        remove_file(file)


def makefile_depends_get_dependencies(depends: str) -> List[str]:
    """Return list with the dependencies of a makefile target.

    Split the makefile depends specification, the name of the dependent is
    followed by ":" its dependencies follow the ":".  There could be spaces
    around the ":".  Line continuation characters, i.e. "\" are consumed by
    the regular expression that splits the specification.

    This results in a list with the dependent first, and its dependencies
    in the remainder of the list, return everything in the list other than
    the first element.
    """
    return re.split(r"[:\s\\]+", re.sub(r"[\s\\]*\Z", "", depends))[1:]


class MakefileAssignment(NamedTuple):
    """Hold the result of splitting a makefile assignment into its parts."""
    variable: str
    value: str


def makefile_assignment_split(assignment: str) -> MakefileAssignment:
    """Split left:=right into a MakefileAssignment.

    Spaces around the := are also removed.
    """
    result = re.split(r"\s*:=\s*", assignment, maxsplit=1)
    if len(result) != 2:
        raise StopError(
            "expected: 'left<optional_spaces>:=<optional_spaces>right' in: " +
            assignment)
    return MakefileAssignment(variable=result[0], value=result[1])


class BuildInfo(NamedTuple):
    """The C source file, its cc_line, and non C source dependencies."""
    source: str
    cc_line: str
    dependencies: List[str]


def get_object_build_info(obj: str) -> Optional[BuildInfo]:
    """Get the BuildInfo for obj.

    If the tool used to produce the object is not the compiler, or if the
    source file is not a C source file None is returned.

    Otherwise it returns a BuildInfo with the C source file name, its cc_line,
    and the remaining dependencies.
    """
    o_cmd = os.path.join(os.path.dirname(obj),
                         "." + os.path.basename(obj) + ".cmd")

    contents = read_file(o_cmd)
    contents = re.sub(r"\$\(wildcard[^)]*\)", " ", contents)
    contents = re.sub(r"[ \t]*\\\n[ \t]*", " ", contents)
    lines = lines_to_list(contents)

    cc_line = None
    deps = None
    source = None
    for line in lines:
        if line.startswith("cmd_"):
            cc_line = line
        elif line.startswith("deps_"):
            deps = line
        elif line.startswith("source_"):
            source = line

    if cc_line is None:
        raise StopError("missing cmd_* variable in: " + o_cmd)
    cc_line = makefile_assignment_split(cc_line).value
    if cc_line.split(maxsplit=1)[0] != COMPILER:
        #   The object file was made by strip, symbol renames, etc.
        #   i.e. it was not the result of running the compiler, thus
        #   it can not contribute to #define compile time constants.
        return None

    if source is None:
        raise StopError("missing source_* variable in: " + o_cmd)
    source = makefile_assignment_split(source).value
    source = source.strip()
    if not source.endswith(".c"):
        return None

    if deps is None:
        raise StopError("missing deps_* variable in: " + o_cmd)
    deps = makefile_assignment_split(deps).value
    dependencies = [HIDDEN_DEP] + deps.split()

    return BuildInfo(source=source, cc_line=cc_line, dependencies=dependencies)


def lines_to_list(lines: str) -> List[str]:
    """Split a string into a list of non-empty lines."""
    return [line for line in lines.strip().splitlines() if line]


def lines_get_first_line(lines: str) -> str:
    """Return the first non-empty line in lines."""
    return lines.strip().splitlines()[0]


def shell_line_to_o_files_list(line: str) -> List[str]:
    """Return a list of .o files in the files list."""
    return [entry for entry in line.split() if entry.endswith(".o")]


def run(args: List[str],
        raise_on_failure: bool = True) -> subprocess.CompletedProcess:
    """Run the program specified in args[0] with the arguments in args[1:]."""
    try:
        #   This argument does not always work for subprocess.run() below:
        #       check=False
        #   neither that nor:
        #       check=True
        #   prevents an exception from being raised if the program that
        #   will be executed is not found

        completion = subprocess.run(args, capture_output=True, text=True)
        if completion.returncode != 0 and raise_on_failure:
            raise StopError("execution failed for: " + " ".join(args))
        return completion
    except OSError as os_error:
        raise StopError("failure executing: " + " ".join(args) + "\n"
                        "original OSError: " + str(os_error.args))


class KernelModule:
    """A kernel module, i.e. a *.ko file."""
    def __init__(self, kofile: str) -> None:
        """Construct a KernelModule object."""
        #   An example argument is used below, assuming kofile is:
        #       possibly/empty/dirs/modname.ko
        #
        #   Meant to refer to this module, shown here relative to the top of
        #   the build directory:
        #       drivers/usb/gadget/udc/modname.ko
        #   the values assigned to the members are shown in the comments below.

        self._file = os.path.realpath(kofile)  # /abs/dirs/modname.ko
        self._base = os.path.basename(self._file)  # modname.ko
        self._directory = os.path.dirname(self._file)  # /abs/dirs
        self._cmd_file = os.path.join(self._directory,
                                      "." + self._base + ".cmd")
        self._cmd_text = read_file(self._cmd_file)

        #   Some builds append a '; true' to the .modname.ko.cmd, remove it

        self._cmd_text = re.sub(r";\s*true\s*$", "", self._cmd_text)

        #   The modules .modname.ko.cmd file contains a makefile snippet,
        #   for example:
        #       cmd_drivers/usb/gadget/udc/dummy_hcd.ko := ld.lld -r ...
        #
        #   Split the string prior to the spaces followed by ":=", and get
        #   the first element of the resulting list.  If the string was not
        #   split (because it did not contain a ":=" then the input string
        #   is returned, by the re.sub() below, as the only element of the list.

        left = makefile_assignment_split(self._cmd_text).variable
        self._rel_file = re.sub(r"^cmd_", "", left)
        if self._rel_file == left:
            raise StopError("expected: 'cmd_' at start of content of: " +
                            self._cmd_file)

        base = os.path.basename(self._rel_file)
        if base != self._base:
            raise StopError("module name mismatch: " + base + " vs " +
                            self._base)

        self._rel_dir = os.path.dirname(self._rel_file)

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
        #       os.path.join(self._rel_dir, kofile_name + ".o")

        kofile_name, _ = os.path.splitext(self._base)
        objs = shell_line_to_o_files_list(self._cmd_text)
        objs.sort()
        expected = [  # sorted, i.e.: .mod.o < .o
            os.path.join(self._rel_dir, kofile_name + ".mod.o"),
            os.path.join(self._rel_dir, kofile_name + ".o")
        ]
        if objs != expected:
            raise StopError("unexpected .o files in: " + self._cmd_file)

    def get_build_dir(self) -> str:
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.

        Note that this, like pretty much all the code, can raise an exception,
        by construction, if an exception is raised while an object is being
        constructed, or after it is constructed, the object will not be used
        thereafter (at least not any object explicitly created by this program)
        Many other places, for example the ones that call read_file() can raise
        exceptions, the code is located where it belongs.

        In this specific case, the computation of index, and the derived
        invariant that it be >= 0, is predicated by the condition checked
        below, if the exception is not raised, then index is >= 0.
        """
        if not self._file.endswith(self._rel_file):
            raise StopError("could not find: " + self._rel_file +
                            " at end of: " + self._file)
        index = len(self._file) - len(self._rel_file)
        if index > 0 and self._file[index - 1] == os.sep:
            index -= 1
        build_dir = self._file[0:index]
        return build_dir

    def get_object_files(self, build_dir: str) -> List[str]:
        """Return a list object files that used to link the kernel module.

        The ocmd_file is the file with extension ".o.cmd" (see below).
        If the ocmd_file has a more than one line in it, its because the
        module is made of a single source file and the ocmd_file has the
        compilation rule and dependencies to build it.  If it has a single
        line single line it is because it builds the .o file by linking
        multiple .o files.
        """

        kofile_name, _ = os.path.splitext(self._base)
        ocmd_file = os.path.join(build_dir, self._rel_dir,
                                 "." + kofile_name + ".o.cmd")
        ocmd_content = read_file(ocmd_file)

        olines = lines_to_list(ocmd_content)
        if len(olines) > 1:  # module made from a single .o file
            return [os.path.join(build_dir, self._rel_dir, kofile_name + ".o")]

        #   Multiple .o files in the module

        ldline = makefile_assignment_split(olines[0]).value
        return [
            os.path.realpath(os.path.join(build_dir, obj))
            for obj in shell_line_to_o_files_list(ldline)
        ]


class Kernel:
    """The Linux kernel component itself, i.e. vmlinux.o."""
    def __init__(self, kernel: str) -> None:
        """Construct a Kernel object."""
        self._kernel = os.path.realpath(kernel)
        self._build_dir = os.path.dirname(self._kernel)
        libs = os.path.join(self._build_dir, "vmlinux.libs")
        objs = os.path.join(self._build_dir, "vmlinux.objs")
        file_must_exist(libs)
        file_must_exist(objs)
        contents = read_file(libs)
        archives_and_objects = contents.split()
        contents = read_file(objs)
        archives_and_objects += contents.split()
        self._archives_and_objects = [(os.path.join(self._build_dir, file)
                                       if not os.path.isabs(file) else file)
                                      for file in archives_and_objects]

    def get_build_dir(self) -> str:
        """Return the top level build directory.

        I.e. the directory where the output of the Linux build is stored.
        """
        return self._build_dir

    def get_object_files(self, build_dir: str) -> List[str]:
        """Return a list object files that where used to link the kernel."""
        olist = []
        for file in self._archives_and_objects:
            if file.endswith(".o"):
                if not os.path.isabs(file):
                    file = os.path.join(build_dir, file)
                olist.append(os.path.realpath(file))
                continue

            if not file.endswith(".a"):
                raise StopError("unknown file type: " + file)

            completion = run(["ar", "t", file])
            objs = lines_to_list(completion.stdout)

            for obj in objs:
                if not os.path.isabs(obj):
                    obj = os.path.join(build_dir, obj)
                olist.append(os.path.realpath(obj))

        return olist


def get_cc_list(obj: str, src: str, cc_line: str) -> List[str]:
    r"""Return the cc_list after validating it and removing some arguments.

    These arguments are removed:
         -Wp,-MD,file.o.d
         -c
         -o foo.o
         foo.c
    Later use of the cc_line is easier because these were removed.

    The cc_line could be fed through
    the shell to deal with the single-quotes in the cc_line that are
    there to quote the double-quotes meant to be part of a C string
    literal.  Specifically, this is done to pass KBUILD_MODNAME and
    KBUILD_BASENAME, for example:
        -DKBUILD_MODNAME='"aes_ce_cipher"'
        -DKBUILD_BASENAME='"aes_cipher_glue"'

    Some kernel modules also pass strings in -D options, and their
    quoting varies, for example (the inner double-quotes are removed
    by the shell, they server no purpose, the outher \ escaped ones
    are passed throgh by the shell):
        -DSDCARDFS_VERSION=\""0.1"\"

    Causing an extra execve(2) of the shell, just for the shell to
    deal with a few quotes is wasteful, the quotes are handled by
    shlex.split().

    Note that the cc_line comes from the .foo.o.cmd file which is a
    makefile snippet, so the actual syntax there is also subject to
    whatever other things make would want to do with them.  Instead
    of doing the absolutely correct thing, which would actually be
    to run them through make to have make run then through the shell,
    this is good enough for now, this program already has knowledge
    about these .cmd files and how they are formed.  This compromise,
    or coupling of knowledge, is a source of fragility, but not
    expected to cause much trouble when the Linux build changes.

    The compiler invocation has this form:
        clang -Wp,-MD,file.o.d  ... -c -o file.o file.c
    there should be at least 5 entries in cc_list, i.e. if the -o
    and file.o are in a single argument value (-ofile.o)."""

    cc_list = shlex.split(cc_line)
    wpmd_flag_ix = -1
    c_flag_ix = -1
    o_flag_ix = -1
    source_ix = -1
    object_ix = -1

    indexes_to_prune = []
    for index, arg in enumerate(cc_list):
        if arg.startswith("-Wp,-MD,"):
            if wpmd_flag_ix >= 0:
                raise StopError(f"multiple -Wp,-MD, arguments for {obj}")
            wpmd_flag_ix = index
        elif arg == "-c":
            if c_flag_ix >= 0:
                raise StopError(f"multiple -c arguments for {obj}")
            c_flag_ix = index
        elif arg.startswith("-o"):
            if o_flag_ix >= 0:
                raise StopError(f"multiple -o arguments for {obj}")
            o_flag_ix = index
        elif arg.endswith(".c"):
            if source_ix >= 0:
                raise StopError(f"multiple .c files for {obj}")
            source_ix = index
        elif arg.startswith("-flto"):
            if arg in {"-flto", "-flto=full", "-flto=thin"}:
                indexes_to_prune.append(index)
        elif arg == "-fsplit-lto-unit":
            indexes_to_prune.append(index)

    indexes_to_prune += [wpmd_flag_ix, c_flag_ix, o_flag_ix, source_ix]

    if wpmd_flag_ix < 0 or c_flag_ix < 0 or o_flag_ix < 0 or source_ix < 0:
        raise StopError("missing arguments for: " + obj + " cc_line: " +
                        cc_line)

    if cc_list[o_flag_ix] == "-o":
        object_ix = o_flag_ix + 1
        if object_ix in indexes_to_prune or object_ix >= len(cc_list):
            raise StopError("bad -o argument for: " + obj + " cc_line: " +
                            cc_line)
        indexes_to_prune.append(object_ix)
    else:
        if not cc_list[o_flag_ix].endswith(".o"):
            raise StopError("bad -o argument for: " + obj + " cc_line: " +
                            cc_line)
        object_ix = o_flag_ix
        cc_list[object_ix] = cc_list[object_ix][2:]

    verify_file(obj, cc_list[object_ix], "object", obj)
    verify_file(src, cc_list[source_ix], "source", obj)
    indexes_to_prune.sort(reverse=True)  # Reverse order makes indexes stable
    for index in indexes_to_prune:
        del cc_list[index]
    return cc_list


def verify_file(file: str, file_in_cc_list: str, kind: str,
                target_file: str) -> None:
    """Ensure file is file_in_cc_list.

    Very few files need normalizing, cheaper to normalize only when needed."""

    if not file.endswith(file_in_cc_list):
        normalized = os.path.normpath(file_in_cc_list)
        if not file.endswith(normalized):
            base = os.path.basename(normalized)

            #   Linux 4.19 sometimes has .tmp_ in the basename of
            #   file_in_cc_list, for example:
            #       arch/arm64/crypto/.tmp_aes-ce-glue.o

            if base[0:5] == ".tmp_":  # verify file without ".tmp_"
                fixed = os.path.join(os.path.dirname(normalized), base[5:])
                if file.endswith(fixed):
                    return
            raise StopError(f"unexpected {kind} argument for: "
                            f"{target_file} value was: "
                            f"{file_in_cc_list}")


class Target:
    """Target of build and the information used to build it."""
    def __init__(self, obj: str, src: str, cc_line: str,
                 deps: List[str]) -> None:
        """Contruct a Target object."""
        if not obj.endswith(".o") or len(obj) <= 2:
            raise StopError("malformed obj argument: " + obj)
        self._obj = obj
        self._src = src
        self._deps = deps
        self._cc_list = get_cc_list(obj, src, cc_line)

    def get_obj(self) -> str:
        """Return the object file for this target."""
        return self._obj

    def generate_defines(self, kmi_dump: str, abi_headers: Set[str]) -> None:
        """Generate the defines for target."""
        object_without_dot_o = self._obj[0:-2]
        vars_o = object_without_dot_o + ".kmi.vars.o"
        if not os.path.isfile(vars_o):
            self.generate_incs_and_vars(object_without_dot_o + ".kmi.incs.c",
                                        object_without_dot_o + ".kmi.vars.c",
                                        vars_o, abi_headers)
        dump_enums(object_without_dot_o + ".kmi.dump", vars_o, kmi_dump)

    def generate_incs_and_vars(self, incs_c: str, vars_c: str, vars_o: str,
                               abi_headers: Set[str]) -> None:
        """Generate the incs and vars C files, and compile the vars file."""
        cc_run = self._cc_list.copy()
        write_file(
            incs_c,
            [f'#include "{dep}"' for dep in self._deps if dep in abi_headers])
        completion = run(cc_run + ["-E", "-dM", "-c", incs_c])

        defines = lines_to_list(completion.stdout)
        defines_without_args = []
        for define in defines:

            #   The value of define is a compiler generated #define,
            #   four forms are possible:
            #       #define NAME
            #       #define MACRO(optional_args)
            #       #define NAME value
            #       #define MACRO(optional_args) value
            #
            #   The define is split into up to 3 parts (2 splits means up to
            #   values result from the slit).  The first two cases above are
            #   ignored, a #define without a value is not a constant for ABI
            #   purposes.  For the last two cases, a MACRO() of any kind (even
            #   it expands into a constant expression) is not handled by this
            #   program, those belong to more complex things to track (such
            #   as inline functions).  Only the third case above matters.

            parts = define.split(maxsplit=2)
            if len(parts) == 3 and '(' not in parts[1]:
                defines_without_args += [(parts[1], parts[2])]

        source_lines = [f'#include "{self._src}"'] + [
            f'typeof({value}) __kmi_v_{name} '
            f'__attribute__ ((section ("KMI_DEFINE"))) = '
            f'({value});' for name, value in defines_without_args
        ]

        inc = os.path.dirname(self._src)
        cc_run += [
            "-ferror-limit=10000", "-I", inc, "-c", vars_c, "-o", vars_o
        ]
        create_and_compile(vars_c, source_lines, cc_run)


def create_and_compile(vars_c: str, source_lines: List[str],
                       cc_run: List[str]) -> None:
    """Create and compile name vars_c with source_lines content.

    Modifies the source_lines while commenting out the lines that have
    initializers that are not constant expressions (they might be link
    time constant expressions, e.g. the address of a varibable, those are
    excluded by kmi_dump.c).
    """
    vars_c_plus_colon = vars_c + ":"
    errors = 0
    attempts = 0
    while attempts < 100:
        attempts += 1
        write_file(vars_c, source_lines)
        completion = run(cc_run, raise_on_failure=False)
        if completion.returncode == 0:
            break
        line_numbers = []
        for line in lines_to_list(completion.stderr):
            if line.startswith(vars_c_plus_colon):
                tokens = line.split(":")
                if len(tokens) < 5 or tokens[3] != " error":
                    continue
                try:
                    number = int(tokens[1])
                    line_numbers.append(number - 1)  # zero based indexes
                except ValueError:
                    continue
        errors += len(line_numbers)
        changed = False
        for number in line_numbers:
            line = source_lines[number]
            if not line.startswith("// "):
                source_lines[number] = "// " + line
                changed = True
        if not changed:
            raise StopError("error commenting impossible for: " + vars_c +
                            ": " + " ".join(cc_run))
    else:
        raise StopError("too many attempts for: " + vars_c)


def dump_enums(dump_file: str, vars_o: str, kmi_dump: str) -> None:
    """Dump compile time constants into a dump file and into an enum file."""
    try:
        if not os.path.exists(dump_file):
            program = [kmi_dump, vars_o]
            with open(dump_file, "w+") as file:
                completion = subprocess.run(program, stdout=file)
            if completion.returncode != 0:
                raise StopError("failed: " + " ".join(program))
    except OSError as os_error:
        raise StopError("failure executing: " + kmi_dump + "\n"
                        "original OSError: " + str(os_error.args))


class KernelComponentBase:
    """Base class for KernelComponentCreationError and KernelComponent.

    There is not much purpose for this class other than to satisfy the strong
    typing checks of pytype, with looser typing, this could be removed but at
    the risk of invoking member functions at run-time on objects that do not
    provide them.  Having this class makes the code more reliable.
    """
    def get_error(self) -> Optional[str]:  # pylint: disable=no-self-use
        """Return None for the error, means there was no error."""
        return None

    def get_deps_set(self) -> Set[str]:  # pylint: disable=no-self-use
        """Return the set of dependencies for the kernel component."""
        return set()

    def get_targets(self) -> List[Target]:  # pylint: disable=no-self-use
        """Return the list of targets in kernel component."""
        #  This function is required by pytype.
        return []

    def is_kernel(self) -> bool:  # pylint: disable=no-self-use
        """Is this the kernel?"""
        return False


class KernelComponentCreationError(KernelComponentBase):
    """A KernelComponent creation error.

    When a KernelComponent creation fails, or the creation of its subordinate
    Kernel or KernelModule creation fails, a KernelComponentCreationError
    object is created to store the information relevant to the failure.
    """
    def __init__(self, filename: str, error: str) -> None:
        """Construct a KernelComponentCreationError object."""
        self._error = error
        self._filename = filename

    def get_error(self) -> Optional[str]:
        """Return the error."""
        return self._filename + ": " + self._error


class KernelComponent(KernelComponentBase):
    """A kernel component, either vmlinux.o or a *.ko file.

    Inspect a Linux kernel module (a *.ko file) or the Linux kernel to
    determine what was used to build it: object filess, source files, header
    files, and other information that is produced as a by-product of its build.
    """
    def __init__(self, filename: str) -> None:
        """Construct a KernelComponent object."""
        if filename.endswith("vmlinux.o"):
            self._kernel = True
            self._kind = Kernel(filename)
        else:
            self._kernel = False
            self._kind = KernelModule(filename)
        self._build_dir = self._kind.get_build_dir()
        self._source_dir = self._get_source_dir()
        self._files_o = self._kind.get_object_files(self._build_dir)
        self._files_o.sort()

        #   using a set because there is no unique flag to list.sort()
        deps_set = set()

        self._targets = []
        for obj in self._files_o:
            file_must_exist(obj)
            build_info = get_object_build_info(obj)
            if build_info is None:
                continue
            src = build_info.source

            file_must_exist(src)
            depends = []
            for dep in build_info.dependencies:
                if not os.path.isabs(dep):
                    dep = os.path.join(self._build_dir, dep)
                dep = os.path.realpath(dep)
                depends.append(dep)
                deps_set.add(dep)

            if not os.path.isabs(src):
                src = os.path.join(self._build_dir, src)
            src = os.path.realpath(src)
            self._targets.append(Target(obj, src, build_info.cc_line, depends))

        for dep in [dep for dep in list(deps_set) if not dep.endswith(".h")]:
            deps_set.remove(dep)
        self._deps_set = deps_set

    def _get_source_dir(self) -> str:
        """Return the top level Linux kernel source directory."""
        source = os.path.join(self._build_dir, "source")
        if not os.path.islink(source):
            raise StopError("could not find source symlink: " + source)

        if not os.path.isdir(source):
            raise StopError("source symlink not a directory: " + source)

        source_dir = os.path.realpath(source)
        if not os.path.isdir(source_dir):
            raise StopError("source directory not a directory: " + source_dir)

        return source_dir

    def get_deps_set(self) -> Set[str]:
        """Return the set of dependencies for the kernel component."""
        return self._deps_set

    def get_targets(self) -> List[Target]:
        """Return the list of targets in kernel component."""
        return self._targets

    def is_kernel(self) -> bool:
        """Is this the kernel?"""
        return self._kernel


def kernel_component_factory(filename: str) -> KernelComponentBase:
    """Make an InfoKmod or an InfoKernel object for file and return it."""
    try:
        return KernelComponent(filename)
    except StopError as stop_error:
        return KernelComponentCreationError(filename,
                                            " ".join([*stop_error.args]))


class KernelComponentProcess(multiprocessing.Process):
    """Process to make the KernelComponent concurrently."""
    def __init__(self) -> None:
        multiprocessing.Process.__init__(self)
        self._queue = multiprocessing.Queue()
        self.start()

    def run(self) -> None:
        """Create and save the KernelComponent."""
        self._queue.put(kernel_component_factory("vmlinux.o"))

    def get_component(self) -> KernelComponentBase:
        """Return the kernel component."""
        kernel_component = self._queue.get()
        self.join()  # must be after queue.get() otherwise it deadlocks
        return kernel_component


def work_on_all_components(options) -> List[KernelComponentBase]:
    """Return a list of KernelComponentBase objects."""
    files = [str(ko) for ko in pathlib.Path().rglob("*.ko")]
    if options.sequential or options.components_sequential:
        return [
            kernel_component_factory(file) for file in ["vmlinux.o"] + files
        ]

    #  There is significantly more work to be done for the vmlinux.o than
    #  the *.ko kernel modules.  A dedicated process is started to do the
    #  work for vmlinux.o as soon as possible instead of leaving it to the
    #  vagaries of multiprocessing.Pool() and how it would spreads the work.
    #  This significantly reduces the elapsed time for this work.

    kernel_component_process = KernelComponentProcess()

    chunk_size = 128
    processes = max(1, len(files) // (chunk_size * 3))
    processes = min(processes, os.cpu_count())
    with multiprocessing.Pool(processes) as pool:
        components = pool.map(kernel_component_factory, files, chunk_size)

    kernel_component = kernel_component_process.get_component()

    return [kernel_component] + components


class TargetError(NamedTuple):
    """Error result of working on a target."""
    object: str
    error: str


def work_on_target(target: Target, kmi_dump: str,
                   abi_headers: Set[str]) -> Optional[TargetError]:
    """Generate defines for target."""
    try:
        target.generate_defines(kmi_dump, abi_headers)
        return None
    except StopError as stop_error:
        return TargetError(object=target.get_obj(),
                           error=" ".join([*stop_error.args]))


def work_on_targets(targets: List[Target], kmi_dump: str,
                    abi_headers: Set[str]) -> List[Optional[TargetError]]:
    """Generate, sequentially, defines for targets."""
    return [
        work_on_target(target, kmi_dump, abi_headers) for target in targets
    ]


class WorkChunk(NamedTuple):
    """A chunk of targets to work on with kmi_dump and abi_headers."""
    targets: List[Target]
    kmi_dump: str
    abi_headers: Set[str]


def work_on_chunk(chunk: WorkChunk) -> List[Optional[TargetError]]:
    """Generate defines for each target in chunk."""
    return work_on_targets(chunk.targets, chunk.kmi_dump, chunk.abi_headers)


def work_on_all_targets(options, components: List[KernelComponentBase],
                        kmi_dump: str,
                        abi_headers: Set[str]) -> List[Optional[TargetError]]:
    """Generate, possibly in parallel, defines for targets in components."""
    targets = []
    for component in components:
        targets += component.get_targets()
    if options.sequential or options.targets_sequential:
        return work_on_targets(targets, kmi_dump, abi_headers)

    #   To avoid using global variables (which actually do not work when
    #   using multiprocessing with the fork server) the kmi_dump and
    #   abi_headers are passed as values.  To avoid passing them as values
    #   for each target, the targets are chunked into chunks which contain
    #   a list of up to chunk_size targets, and the values of kmi_dump and
    #   abi_headers.  Thus the cost of passing them repeatedly is amortized.
    #   The actual chunking is done prior to pool.map(), thus its chunk_size
    #   argument is 1.

    chunk_size = 128
    chunks = [
        WorkChunk(targets=targets[ix:ix + chunk_size],
                  kmi_dump=kmi_dump,
                  abi_headers=abi_headers)
        for ix in range(0, len(targets), chunk_size)
    ]
    with multiprocessing.Pool(os.cpu_count()) as pool:
        result_lists = pool.map(work_on_chunk, chunks, 1)
    results = []
    for result_list in result_lists:
        results += result_list
    return results


def work_on_whole_build(options, kmi_dump: str) -> int:
    """Work on the whole build to extract the #define constants."""
    if not os.path.isfile("vmlinux.o"):
        logging.error("file not found: vmlinux.o")
        return 1

    exclude = {
        header
        for header in [
            os.path.realpath(os.path.join("source", exclude_header))
            for exclude_header in EXCLUDE
        ] if os.path.isfile(header)
    }

    logging.info("work on all components: started")
    components = work_on_all_components(options)
    logging.info("work on all components: finished")

    failed = False
    logging.info("header counts: started")
    header_count = collections.defaultdict(int)
    for comp in components:
        error = comp.get_error()
        if error:
            logging.error(error)
            failed = True
            continue
        if not options.use_includes:
            for header in comp.get_deps_set():
                header_count[header] += 1
    logging.info("header counts: finished")

    if options.dump:
        dump(components)
    if failed:
        return 1

    logging.info("abi header set: started")
    abi_headers = {
        header
        for header in lines_to_list(read_whole_file("kmi.headers"))
    } if options.use_includes else {
        header
        for header, count in header_count.items()
        if count >= 2 and header not in exclude
    }
    logging.info("abi header set: finished")

    if options.save_includes:
        abi_headers_list = list(abi_headers)
        abi_headers_list.sort()
        write_whole_file("kmi.headers", abi_headers_list)

    if options.components_only:
        return 0

    exit_status = 0
    logging.info("work on all targets: started")
    results = work_on_all_targets(options, components, kmi_dump, abi_headers)
    logging.info("work on all targets: finished")
    for result in results:
        if result:
            logging.error(result.object + ": " + result.error)
            exit_status = 1
    return exit_status


def get_compiler() -> Optional[str]:
    """Determine if the compiler is in the prebuilts binaries."""
    path = os.getenv("PATH")
    if path is None:
        logging.error("PATH is not set")
        return None
    compiler = None
    for directory in path.split(os.pathsep):  # i.e. ":" not os.path.sep
        compiler_in_directory = os.path.join(directory, COMPILER)
        if os.path.exists(compiler_in_directory):
            compiler = compiler_in_directory
            break
    else:
        logging.error("could not find compiler in PATH")
        return None
    prebuilts = os.path.realpath(
        os.path.join(os.getcwd(), "source/../prebuilts-master"))
    if compiler is None:
        logging.error("cold not find compiler")
        return None
    if not compiler.startswith(prebuilts):
        logging.error("compiler: " + compiler + " not inside: " + prebuilts)
        return None
    return compiler


def update_kmi_dump() -> Optional[str]:
    """Recompile kmi_dump from kmi_dump.c if it missing or out of date."""
    kmi_dump_c = os.path.realpath(
        os.path.join(os.getcwd(), "source/../build/abi/kmi_dump.c"))
    kmi_dump = kmi_dump_c[0:-2]
    if not os.path.exists(kmi_dump_c):
        logging.error("could not find kmi_dump.c")
        return None
    if (not os.path.exists(kmi_dump)
            or os.path.getmtime(kmi_dump_c) >= os.path.getmtime(kmi_dump)):
        completion = run([COMPILER, "-O2", "-o", kmi_dump, kmi_dump_c],
                         raise_on_failure=False)
        if completion.returncode != 0:
            logging.error("compilation failed for kmi_dump.c")
            return None
    return kmi_dump


def print_enum(out: TextIO, name: str, value: str) -> None:
    """Print data as enum declarations into the out file."""

    #   Beware of value having additional ":" characters, for example:
    #       15:0x5b,0x44,0x65,0x70,...,0x20,0x00:"[Deprecated]: "
    #   Without maxsplit=2, those extra ":" characters would cause fields[2]
    #   (i.e. cstr) not to have all of the data in the third field.

    fields = value.split(":", maxsplit=2)
    size, data, cstr = int(fields[0]), fields[1], fields[2]

    if len(cstr) > 4:  # either: ':\n', ':""\n', or ':"something"\n'
        print(f"// {cstr}", end="", file=out)

    print(f"enum __kmi_s_{name} {{__kmi_size_{name} = {size}}};", file=out)
    if size in {0, 1, 2, 4, 8}:
        if size == 0:
            data = 0
        print(f"enum __kmi_d_{name} {{__kmi_data_{name} = {data}}};\n",
              file=out)
        return

    vals = data.split(",")

    for num, val in enumerate(vals):
        print(f"enum __kmi_d{num}_{name} {{__kmi_data{num}_{name} = {val}}};",
              file=out)

    print(f"union __kmi_w_{name} {{", file=out)
    print("\tint __kmi_dummy;", file=out)
    for num, val in enumerate(vals):
        print(f"\tenum __kmi_d{num}_{name} __kmi_ud{num}_{name};", file=out)
    print("};\n", file=out)


def print_union(out: TextIO, name: str, value: str, group: str,
                unions: List[str]) -> str:
    """Print data as union declarations into the out file.

    Unions with too many fields might cause trouble with the compiler
    for long term stability of the generated declarations it is best to
    split the union declarations into a series of union declarations
    with a final union of those unions.

    The initial group is None, thereafter, the value of group is the
    value returned by this function which can insert new union group
    declarations when required.

    The unions list contains all the group unions declared by repeated
    invocations of this function.
    """

    fields = value.split(":")
    size = int(fields[0])

    new_group = name[0:4]
    if group != new_group:
        if group is not None:
            print("};\n", file=out)
        group = new_group
        unions.append(group)
        print(f"union __kmi_u_{group} {{", file=out)
        print("\tint __kmi_dummy;", file=out)

    print(f"\tenum __kmi_s_{name} __kmi_sz_{name};", file=out)
    if size in {0, 1, 2, 4, 8}:
        print(f"\tenum __kmi_d_{name} __kmi_ef_{name};", file=out)
    else:
        print(f"\tunion __kmi_w_{name} __kmi_uf_{name};", file=out)

    return group


def print_union_finish(out: TextIO, unions: List[str]) -> None:
    """Close the last union and declare the union of all the unions."""
    print("};\n", file=out)
    print(f"union __kmi_union {{", file=out)
    print("\tint __kmi_dummy;", file=out)
    for union in unions:
        print(f"\tunion __kmi_u_{union} __kmi_uu_{union};", file=out)
    print("};\n", file=out)


class Define(NamedTuple):
    """A #define with its name and its list of values, usually just one."""
    name: str
    values: List[str]


def get_defines() -> List[Define]:
    """Generate and return the list of defines.

    A large number of .kmi.dump files with very large amounts of redundant
    data need to be sorted and uniquified.  The data is so large that reducing
    the redundancy first and then sorting is much faster (reducing the data
    through a hash, i.e. a set(), has order N cost, even if it has a high
    constant cost).
    """
    logging.info("build set started")
    defines_set = set()
    for file in pathlib.Path().rglob("*.kmi.dump"):
        with open(file) as dumpfile:
            defines_set |= set(dumpfile)
    logging.info("build set finished")

    #   Multiple defines with different values might exist, a dictionary
    #   with the define name as its key is used, the value is a set of
    #   all of its unique values.

    logging.info("build dict started")
    defines_dict = dict()
    for line in defines_set:
        name, value = line.split(":", maxsplit=1)
        define_values = defines_dict.get(name, set())
        define_values.add(value)
        defines_dict[name] = define_values
    logging.info("build dict finished")

    logging.info("build and sort list started")
    defines = [
        Define(name=name, values=list(values))
        for name, values in defines_dict.items()
    ]
    defines.sort()
    logging.info("build and sort list finished")

    return defines


def write_kmi_files(uniq_file: TextIO, dups_file: TextIO,
                    dupcounts_file: TextIO, enums_file: TextIO,
                    union_file: TextIO) -> None:
    """Write the kmi.* files."""
    group = None
    unions = []
    for define in get_defines():
        count = len(define.values)
        if count == 1:
            value = define.values[0]
            print(define.name, value, sep=":", end="", file=uniq_file)
            print_enum(enums_file, define.name, value)
            group = print_union(union_file, define.name, value, group, unions)
        else:
            print(define.name, count, sep=":", file=dupcounts_file)
            define.values.sort()
            for value in define.values:
                print(define.name, value, sep=":", end="", file=dups_file)
    print_union_finish(union_file, unions)


def generate_kmi_files(compiler: str) -> int:
    """Generate top level kmi output files."""
    try:
        with open("kmi.uniq.tmp", "w+") as uniq_file, \
             open("kmi.dups.tmp", "w+") as dups_file, \
             open("kmi.dupcounts.tmp", "w+") as dupcounts_file, \
             open("kmi_enums.h.tmp", "w+") as enums_file, \
             open("kmi_union.h.tmp", "w+") as union_file:
            write_kmi_files(uniq_file, dups_file, dupcounts_file, enums_file,
                            union_file)
        os.rename("kmi.uniq.tmp", "kmi.uniq")
        os.rename("kmi.dups.tmp", "kmi.dups")
        os.rename("kmi.dupcounts.tmp", "kmi.dupcounts")
        os.rename("kmi_enums.h.tmp", "kmi_enums.h")
        os.rename("kmi_union.h.tmp", "kmi_union.h")
        write_whole_file("kmi.c", KMI_C)
    except OSError:
        logging.error("creation of kmi.* files failed")
        remove_kmi_files()
        return 1
    completion = subprocess.run([compiler, "-g", "-c", "kmi.c"])
    if completion.returncode != 0:
        logging.error("compilation of kmi.c failed")
        return 1
    return 0


def remove_kmi_files() -> None:
    """Remove the top level output files."""
    remove_files([
        "kmi.uniq",
        "kmi.uniq.tmp",
        "kmi.dups",
        "kmi.dups.tmp",
        "kmi.dupcounts",
        "kmi.dupcounts.tmp",
        "kmi_enums.h",
        "kmi_enums.h.tmp",
        "kmi_union.h"
        "kmi_union.h.tmp",
        "kmi.c",
        "kmi.o",
    ])


def remove_other_kmi_files(options) -> None:
    """Optionally remove target files and kmi.headers.

    The per target files can be requested to be kept.
    The kmi.headers file is only removed if it will be saved."""

    if options.save_includes:
        remove_file("kmi.headers")
    if not options.keep_target_files:
        for file in pathlib.Path().rglob("*.kmi.dump"):
            os.remove(file)
        for file in pathlib.Path().rglob("*.kmi.incs.c"):
            os.remove(file)
        for file in pathlib.Path().rglob("*.kmi.vars.[co]"):
            os.remove(file)


def init_multiprocessing_work(main_pid: int) -> bool:
    """Dummy to get fork server started early."""
    return main_pid != os.getpid()


def init_multiprocessing(options) -> bool:
    """Initialize multiprocessing."""

    if options.sequential or (options.components_sequential
                              and options.targets_sequential):
        return True

    #  Ensure fork server is created before this process gets big.
    #  Could not find an API to cause the fork server to be created,
    #  seems to be created lazily, this workaround is not too bad.

    multiprocessing.set_start_method('forkserver')
    with multiprocessing.Pool(2) as pool:
        result = pool.map(init_multiprocessing_work, [os.getpid()], 1)
    return result[0]


def main() -> int:
    """Extract #define compile time constants from a Linux build."""
    def existing_file(file):
        if not os.path.isfile(file):
            raise argparse.ArgumentTypeError(
                "{0} is not a valid file".format(file))
        return file

    parser = argparse.ArgumentParser()
    parser.add_argument("-o",
                        "--components-only",
                        action="store_true",
                        help="work on components and stop")
    parser.add_argument("-k",
                        "--keep-target-files",
                        action="store_true",
                        help="keep per target intermediate files: *.kmi.*")
    parser.add_argument("-s",
                        "--sequential",
                        action="store_true",
                        help="execute without concurrency")
    parser.add_argument("-C",
                        "--components-sequential",
                        action="store_true",
                        help="work on components sequentially")
    parser.add_argument("-T",
                        "--targets-sequential",
                        action="store_true",
                        help="work on targets sequentially")
    parser.add_argument("-d",
                        "--dump",
                        action="store_true",
                        help="dump internal state")
    parser.add_argument("-I",
                        "--info",
                        action="store_true",
                        help="enable INFO log level")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-i",
                       "--save-includes",
                       action="store_true",
                       help="save headers to: kmi.headers")
    group.add_argument("-u",
                       "--use-includes",
                       action="store_true",
                       help="use headers in: kmi.headers")
    group.add_argument("-c",
                       "--component",
                       type=existing_file,
                       help="show information for a component")
    group.add_argument("-g",
                       "--generate-only",
                       action="store_true",
                       help="only generate kmi.* and kmi*.[hc] files")
    options = parser.parse_args()

    logging_kwargs = {
        'format':
        "%(asctime)-15s: " + os.path.basename(sys.argv[0]) + ": %(message)s"
    }
    if options.info:
        logging_kwargs["level"] = logging.INFO
    logging.basicConfig(**logging_kwargs)

    if not init_multiprocessing(options):
        logging.error("multiprocessing initialization failed")
        return 1

    if options.component:
        comp = kernel_component_factory(options.component)
        error = comp.get_error()
        if error:
            logging.error(error)
            return 1
        if options.dump:
            dump([comp])
        return 0

    compiler = get_compiler()
    if compiler is None:
        return 1

    remove_kmi_files()
    if not options.generate_only:
        kmi_dump = update_kmi_dump()
        if kmi_dump is None:
            return 1
        remove_other_kmi_files(options)
        status = work_on_whole_build(options, kmi_dump)
        if status:
            return status

    return generate_kmi_files(compiler)


if __name__ == "__main__":
    sys.exit(main())
