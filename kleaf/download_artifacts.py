#!/usr/bin/env python3
# #
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
import collections
import functools
import io
import os.path
import urllib.request
import json
import http.client


class OneProgress(object):
    def __init__(self, expect_len: int):
        self.passed = 0
        self.expect_len = expect_len

    def __iadd__(self, other: int):
        self.passed += other

    def __str__(self):
        return "{}/{}({}%)".format(self.passed, self.expect_len,
                                   self.passed / self.expect_len * 100)


PROGRESS: dict[str, OneProgress] = {}


def dump_file(src: io.IOBase, dst: io.IOBase, expect_len: int = None,
              name: str = None) -> None:
    while True:
        buf = src.read(4096)
        if not buf:
            break
        dst.write(buf)
        if name:
            if name not in PROGRESS:
                PROGRESS[name] = OneProgress(expect_len)
            PROGRESS[name] += len(buf)


def download_to(url: str, out: str, file: str, hook=None,
                verbose: bool = False) -> None:
    output_file = os.path.join(out, file)
    req = urllib.request.Request(url=url)
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(debuglevel=1 if verbose else 0),
    )
    with opener.open(req) as resp:
        if hook is not None and hook(resp, out, file):
            return
        with open(output_file, "wb") as f:
            dump_file(resp, f, expect_len=resp.getheader("Content-Length"),
                      name=file)


def signed_url_hook(resp: http.client.HTTPResponse, out: str, file: str,
                    verbose: bool = False) -> bool:
    """
    If /url returns JSON, find the signed URL from it, and download the signed URL instead.
    """
    if resp.getheader("Content-Type") == "application/json":
        jsontext = resp.read()
        try:
            signed_url = json.loads(jsontext)["signedUrl"]
        except (ValueError, KeyError) as e:
            print("URL={}\nCode={}, Response is\n{}".format(resp.geturl(),
                                                            resp.status,
                                                            jsontext))
            raise e
        download_to(signed_url, out, file, verbose=verbose)
        return True


def download_artifact(build_number: str, target: str, file: str, out: str,
                      verbose: bool = False) -> None:
    url = f"https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{file}/url"
    download_to(url, out, file, signed_url_hook, verbose=verbose)


async def async_exec(fn):
    return await asyncio.get_running_loop().run_in_executor(None, fn)


async def download_artifacts(build_number: str, target: str, files: list[str],
                             out: str, verbose: bool = False) -> None:
    """Download artifacts from a kernel build from ci.android.com"""
    aws = [async_exec((functools.partial(download_artifact,
                                         build_number=build_number,
                                         target=target,
                                         file=file,
                                         out=out,
                                         verbose=verbose,
                                         ))) for file in files]
    await asyncio.gather(*aws)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=download_artifacts.__doc__)
    parser.add_argument("--files", nargs="*",
                        help="A list of file names to download")
    parser.add_argument("--build_number", required=True,
                        help="Build number")
    parser.add_argument("--target", default="kernel_kleaf",
                        help="Target name")
    parser.add_argument("--out", required=True,
                        help="Output directory")
    parser.add_argument("--verbose", action="store_true",
                        help="Print verbose output")
    args = parser.parse_args()
    asyncio.run(download_artifacts(**vars(args)))
