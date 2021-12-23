#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
from http.client import HTTPResponse
import io
import json
import os.path
import sys
import time
import traceback
import urllib.request
from typing import Optional, Callable


class Progress(object):
    def __init__(self, expect_len: Optional[int]):
        self.passed: int = 0
        self.expect_len: Optional[int] = expect_len

    def __iadd__(self, other: int):
        self.passed += other
        return self

    def __str__(self):
        percentage = f"{self.passed / self.expect_len * 100:.2f}" if self.expect_len else '??'
        return f"{self.passed}/{self.expect_len}({percentage}%)"


class ProgressPrint(object):
    PRINT_INTERVAL_NS: int = 5 * 10 ** 8  # 0.5s

    def __init__(self, expect_len: Optional[int], verbose: int):
        self.last_print: Optional[int] = None
        self.progress: Optional[Progress] = None
        if verbose:
            self.progress = Progress(expect_len=expect_len)

    def update(self, addition: int):
        if self.progress is None:
            return
        self.progress += addition

        if self.last_print is None or (
                time.monotonic_ns() - self.last_print > ProgressPrint.PRINT_INTERVAL_NS):
            self.force_print()
            self.last_print = time.monotonic_ns()

    def force_print(self):
        if self.progress is None:
            return
        sys.stdout.write(f"{self.progress}\r")


def dump_file(src: io.IOBase, dst: io.IOBase, expect_len: Optional[int] = None,
              verbose: int = 0) -> None:
    """
    Dump src to dst.
    """
    progress = ProgressPrint(expect_len=expect_len, verbose=verbose)
    while True:
        buf = src.read(1024 * 1024)
        if not buf:
            break
        dst.write(buf)
        progress.update(len(buf))
    progress.force_print()


def download_to(url: str, output_file: str, verbose: int = 0,
                hook: Callable[[HTTPResponse, str, int], bool] = None) -> None:
    """
    Download url to output_file.

    If hook is specified, hook(response) is executed upon receiving response.
    The hook should return True if it has handled the response.
    """
    req = urllib.request.Request(url=url)
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(debuglevel=1 if verbose >= 2 else 0),
    )
    try:
        with opener.open(req) as resp:
            if hook is not None and hook(resp, output_file, verbose):
                return
            with open(output_file, "wb") as f:
                expect_len = None
                try:
                    expect_len = int(resp.getheader("Content-Length"))
                except ValueError:
                    traceback.print_exc()
                dump_file(src=resp, dst=f, expect_len=expect_len, verbose=verbose)
    except:
        sys.stderr.write(f"For URL {url}\n")
        raise


def signed_url_hook(resp: HTTPResponse, output_file: str, verbose: int = 0) -> bool:
    """
    If /url returns JSON, find the signed URL from it, and download the signed URL instead.
    """
    if resp.getheader("Content-Type") != "application/json":
        return False

    json_text = resp.read()
    try:
        signed_url = json.loads(json_text)["signedUrl"]
    except (ValueError, KeyError) as e:
        print(
            f"URL={resp.geturl()}\nCode={resp.status}, Response is\n{json_text}")
        raise e
    # This is the real URL, so no need to pass hook again.
    download_to(url=signed_url, output_file=output_file, verbose=verbose)
    return True


def download_artifact(build_number: str, target: str, file: str,
                      out: str, verbose: int = 0) -> None:
    """Download an artifact from a kernel build from ci.android.com"""
    download_to(
        url=f"https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{file}/url",
        output_file=os.path.join(out, file),
        verbose=verbose,
        hook=signed_url_hook,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=download_artifact.__doc__)
    parser.add_argument("--file", required=True,
                        help="File name to download")
    parser.add_argument("--build_number", required=True,
                        help="Build number")
    parser.add_argument("--target", default="kernel_kleaf",
                        help="Target name.")
    parser.add_argument("--out", required=True,
                        help="Output directory")
    parser.add_argument("-v", "--verbose", action="count", default=0,
                        help="""Print verbose output.
                                If not specified, remain silent.
                                -v: Print progress.
                                -vv: Print progress and HTTP logs.""")
    args = parser.parse_args()

    download_artifact(**vars(args))
