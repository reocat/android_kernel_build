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
import asyncio
import http.client
import io
import json
import os.path
import sys
import traceback
import urllib.request


class OneProgress(object):
    def __init__(self, expect_len: int):
        self.passed = 0
        self.expect_len = expect_len

    def __iadd__(self, other: int):
        self.passed += other
        return self

    def __str__(self):
        percentage = f"{self.passed / self.expect_len * 100:.2f}" if self.expect_len else '??'
        return f"{self.passed}/{self.expect_len}({percentage}%)"


class Progress(dict[str, OneProgress]):
    def __str__(self):
        return "; ".join([f"{k}: {v}" for k, v in self.items()])


PROGRESS = Progress()


async def print_progress_periodic():
    """
    Print PROGRESS periodically on the console.
    """
    while True:
        sys.stdout.write(f"{PROGRESS}\r")
        await asyncio.sleep(1)


async def dump_file(src: io.IOBase, dst: io.IOBase, expect_len: int = None,
                    name: str = None, verbose: int = 0) -> None:
    """
    Dump src to dst.
    """
    while True:
        buf = src.read(1024 * 1024)
        if not buf:
            break
        dst.write(buf)
        if name:
            if name not in PROGRESS:
                PROGRESS[name] = OneProgress(expect_len)
            PROGRESS[name] += len(buf)
            if verbose:
                await asyncio.sleep(0)  # Yield to print_progress_periodic
    sys.stdout.write(f"{PROGRESS}\r")


async def download_to(url: str, out: str, file: str, verbose: int = 0,
                      hook=None) -> None:
    """
    Download url to out/file.

    If hook is specified, hook(response) is executed upon receiving response.
    The hook should return True if it has handled the response.
    """
    output_file = os.path.join(out, file)
    req = urllib.request.Request(url=url)
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(debuglevel=1 if verbose >= 2 else 0),
    )
    with opener.open(req) as resp:
        if hook is not None and hook(resp, out, file):
            return
        with open(output_file, "wb") as f:
            expect_len = None
            try:
                expect_len = int(resp.getheader("Content-Length"))
            except ValueError:
                traceback.print_exc()
            await dump_file(src=resp, dst=f, expect_len=expect_len, name=file,
                            verbose=verbose)


def signed_url_hook(resp: http.client.HTTPResponse, out: str, file: str,
                    verbose: int = 0) -> bool:
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
    download_to(url=signed_url, out=out, file=file, verbose=verbose)
    return True


async def download_artifacts(build_number: str, target: str, files: list[str],
                             out: str, verbose: int = 0) -> None:
    """Download artifacts from a kernel build from ci.android.com"""
    print_progress_task = None
    if verbose:
        print_progress_task = asyncio.create_task(print_progress_periodic())
    tasks = [asyncio.create_task(download_to(
        url=f"https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{file}/url",
        file=file,
        out=out,
        verbose=verbose,
        hook=signed_url_hook,
    )) for file in files]
    await asyncio.gather(*tasks)
    if verbose:
        print_progress_task.cancel()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=download_artifacts.__doc__)
    parser.add_argument("--files", nargs="*",
                        help="A list of file names to download")
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

    asyncio.run(download_artifacts(**vars(args)))
