import errno
import fcntl
import os
import sys
import textwrap


def die(msg):
    sys.stderr.write(textwrap.dedent(f"""\
        ERROR: Collision in {sys.argv[1]} detected! ({msg})
            Run `tools/bazel clean` then try building again.
            If the error persists, report a bug.
        """))
    sys.exit(1)


class LockedFile(object):
    def __init__(self, path: str):
        self._path = path

    def __enter__(self):
        self._fd = os.open(self._path, os.O_RDWR | os.O_CREAT)
        try:
            fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as e:
            if e.errno == errno.EACCES or e.errno == errno.EAGAIN:
                die("File is already locked")
            die(str(e))
        return self._fd

    def __exit__(self, exc_type, exc_value, exc_traceback):
        fcntl.flock(self._fd, fcntl.LOCK_UN)
        os.close(self._fd)
        self._fd = None


def copy_content(in_fd: int, out_fd: int):
    """Copies the content of in_fd into out_fd."""
    while True:
        buf = os.read(in_fd, 4096)
        if not buf:
            break
        os.write(out_fd, buf)


def comp_file(in_fd: int, out_fd: int) -> bool:
    """Compares the content of two file descriptors."""
    while True:
        in_buf = os.read(in_fd, 4096)
        out_buf = os.read(out_fd, 4096)

        if in_buf != out_buf:
            return False

        if not in_buf:
            return True


def comp_write(in_fd: int, out_fd: int) -> bool:
    """Returns True iff in_fd has the same content of out_fd, or out_fd is empty.

    If out_fd is empty, write in_fd into out_fd.
    """
    out_file_has_content = os.pread(out_fd, 1, 0)

    if not out_file_has_content:
        copy_content(in_fd, out_fd)
        return True

    return comp_file(in_fd, out_fd)


with LockedFile(sys.argv[1]) as locked_fd:
    out_content = os.pread(locked_fd, 4096, 0)

    if not comp_write(sys.stdin.fileno(), locked_fd):
        die("File content changes")