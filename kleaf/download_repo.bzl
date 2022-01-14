# Copyright (C) 2022 The Android Open Source Project
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

load("//build/kleaf:utils.bzl", "sanitize_repo_name")

_URL_MAP_ENV_VAR = "KLEAF_DOWNLOAD_REPO_URL_MAP"
_BUILD_NUM_ENV_VAR = "KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"

def _parse_env(repository_ctx, var_name, expected_key):
    """
    Given that the environment variable named by `var_name` is set to the following:

    ```
    # single-line comment (trailing comment not supported)
    key=value
    ```

    Return a list of values, where key matches `expected_key`. Multiple matches are accumulated.

    For example:
    ```
    --action_env=MYVAR="
        myrepo=file:///x
        myrepo=file:///y
    "
    ```

    Then `_parse_env(repository_ctx, "MYVAR", "myrepo")` returns

    ```
    ["file:///x", "file:///y"]
    ```
    """
    ret = []
    for line in repository_ctx.os.environ.get(var_name, "").splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            continue

        # repo=url
        tup = line.split("=", 1)
        if len(tup) != 2:
            fail("Unrecognized line in {}, must be key=value:\n{}".format(var_name, line))
        key, value = tup
        if key != expected_key:
            continue
        ret.append(value)
    return ret

def _download_repo_impl(repository_ctx, override_urls = None):
    env_urls = _parse_env(repository_ctx, _URL_MAP_ENV_VAR, repository_ctx.name)
    if env_urls:
        print("@{}: URLs change to {}".format(repository_ctx.name, env_urls[0] if len(env_urls) == 1 else env_urls))
        urls = env_urls
    elif override_urls:
        urls = override_urls
    else:
        urls = repository_ctx.attr.urls

    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file)

    build_file = """filegroup(name="file", srcs=["{}"], visibility=["//visibility:public"])
""".format(repository_ctx.attr.downloaded_file_path)
    repository_ctx.file("file/BUILD.bazel", build_file)

    download_path = repository_ctx.path("file/{}".format(repository_ctx.attr.downloaded_file_path))
    download_info = repository_ctx.download(
        url = urls,
        output = download_path,
        sha256 = repository_ctx.attr.sha256,
    )

download_repo = repository_rule(
    implementation = _download_repo_impl,
    doc = """Create a repository containing a file downloaded from a given list of mirror URLs.

This is similar to [`http_file`](https://docs.bazel.build/versions/main/repo/http.html#http_file)
but allows the URLs to be overridden via
[`--action-env`](https://docs.bazel.build/versions/main/command-line-reference.html#flag--action_env)`=KLEAF_DOWNLOAD_REPO_URL_MAP`.

Example:

```
download_repo(
    name = "myrepo",
    urls = ["https://some-url/x", "https://mirror-url/x"]
)
```

Then download with

```
bazel build @myrepo//file
```

The result would be to fetch `@myrepo//file` from `https://some-url/x`, and if that fails, fallback
to `https://mirror-url/x`.

You may refer to the downloaded file with label `@myrepo//file`.

""",
    attrs = {
        "urls": attr.string_list(
            mandatory = False,
            doc = """A list of mirror URLs.

See
[`repository_ctx.download`](https://docs.bazel.build/versions/main/skylark/lib/repository_ctx.html#download).

The values in the dictionary may be overridden by environment variable
`KLEAF_DOWNLOAD_REPO_URL_MAP`. The environment variable contains a mapping from the repo name to
a list of URLs to replace this attribute. Multiple values are accumulated.

For example, if the following is specified in `WORKSPACE`:

```
download_repo(
    name = "myrepo",
    urls = ["https://some-url/x", "https://mirror-url/x"],
)
```

Then build with:

```
bazel build --action_env=KLEAF_DOWNLOAD_REPO_URL_MAP="
    # single-line comment (trailing comment not supported)
    myrepo=file:///x
    myrepo=file:///mirror-x
" @myrepo//...
```

This is equivalent to

```
download_repo(
    name = "myrepo",
    urls = ["file:///x", "file:///mirror-x"],
)
```

The result would be to fetch `@myrepo//file` from `file:///x`, and if that fails, fallback
to `file:///mirror-x`.

""",
        ),
        "sha256": attr.string(
            mandatory = False,
            default = "",
            doc = """The expected SHA-256 of the downloaded file.

If not specified, no hash check is performed on the downloaded artifact. See
[`repository_ctx.download`](https://docs.bazel.build/versions/main/skylark/lib/repository_ctx.html#download).

""",
        ),
        "downloaded_file_path": attr.string(
            default = "downloaded",
            doc = "Path assigned to the file downloaded",
        ),
    },
    environ = [
        _URL_MAP_ENV_VAR,
    ],
)

_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{filename}/url?redirect=true"

# Instead of having download_artifacts_repo call download_repo directly, a
# separate repository_rule, _download_artifact_repo, is needed because macros
# can't access environment variables, therefore the URL cannot be constructed
# based on environment variables in the macro. So we have to access environment
# variables in the impl of this helper rule, then invoke _download_repo_impl.
def _download_artifact_repo_impl(repository_ctx):
    env_build_numbers = _parse_env(repository_ctx, _BUILD_NUM_ENV_VAR, repository_ctx.attr.prefix)
    if len(env_build_numbers) > 1:
        fail("{prefix}: Seen multiple build numbers in {var_name}: {build_numbers}".format(
            prefix = repository_ctx.attr.prefix,
            var_name = _BUILD_NUM_ENV_VAR,
            build_numbers = env_build_numbers,
        ))
    if env_build_numbers:
        build_number = env_build_numbers[0]
    else:
        build_number = repository_ctx.attr.build_number

    if not build_number:
        SAMPLE_BUILD_NUMBER = "8077484"
        fail("""ERROR: {prefix}: No build_number specified.

Fix by one of the following:
- Specify `build_number` attribute in {prefix}
- Specify `--action_env={build_num_var}="{prefix}=<build_number>"`, e.g.
    bazel build \\
      --action_env={build_num_var}="{prefix}={build_number}" \\
      @{repo_name}//file
- Specify `--action_env={url_var}="{prefix}=<url>"`, e.g.
    bazel build \\
      --action_env={url_var}="{prefix}={url}" \\
      @{repo_name}//file
""".format(
            repo_name = repository_ctx.name,
            prefix = repository_ctx.attr.prefix,
            build_number = SAMPLE_BUILD_NUMBER,
            build_num_var = _BUILD_NUM_ENV_VAR,
            url_var = _URL_MAP_ENV_VAR,
            url = _ARTIFACT_URL_FMT.format(
                build_number = SAMPLE_BUILD_NUMBER,
                target = repository_ctx.attr.target,
                filename = repository_ctx.attr.downloaded_file_path,
            ),
        ))

    _download_repo_impl(repository_ctx, override_urls = [_ARTIFACT_URL_FMT.format(
        build_number = build_number,
        target = repository_ctx.attr.target,
        filename = repository_ctx.attr.downloaded_file_path,
    )])

_download_artifact_repo = repository_rule(
    implementation = _download_artifact_repo_impl,
    attrs = {
        "build_number": attr.string(),
        "prefix": attr.string(),
        "target": attr.string(),
        "downloaded_file_path": attr.string(),
        "sha256": attr.string(default = ""),
    },
    environ = [
        _URL_MAP_ENV_VAR,
        _BUILD_NUM_ENV_VAR,
    ],
)

def download_artifacts_repo(
        prefix,
        target,
        files,
        build_number = None):
    """Create a repository that contains artifacts downloaded from [ci.android.com](http://ci.android.com).

    A repository is created for each item in `files`, named `{prefix}_{sanitized_file}`, where
    `sanitized_file` is item in `files`, sanitized by (`sanitize_repo_name`)[#sanitize_repo_name].

    For example:
    ```
    load("//build/kleaf:constants.bzl", "aarch64_outs")
    download_artifacts_repo(
        prefix = "gki_prebuilts",
        target = "kernel_kleaf",
        build_number = "8077484"
        files = aarch64_outs,
    )
    ```

    You may refer to the files with the label `@downloaded_vmlinux//file`, etc.

    You may leave the build_number empty. If so, you must override the build number at build time.
    See below.

    You may override the build number in the command line with one of the following methods:

    1. (Highest priority) Specify the URL via `KLEAF_DOWNLOAD_REPO_URL_MAP`.
       See [download_repo](#download_repo).

       This is primarily used for truly offline builds, where the artifacts may be cached locally
       and pointed to via `file://` links. This is not recommended to be used in daily development
       as the URLs are long and subject to change.

    2. Specify the build number via `KLEAF_DOWNLOAD_BUILD_NUMBER`.

       In the above example, you may override the build number to `8078291` with:

       ```
       bazel build \\
           --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER="gki_prebuilts=8078291" \\
           @gki_prebuilts_vmlinux//file
       ```

    Args:
        prefix: prefix of the repositories created.
        target: build target on [ci.android.com](http://ci.android.com)
        build_number: build number on [ci.android.com](http://ci.android.com)
        files: One of the following:

          - If a list, this is a list of file names on [ci.android.com](http://ci.android.com).
          - If a dict, keys are file names on [ci.android.com](http://ci.android.com), and values
            are corresponding SHA256 hash.
    """

    if type(files) == type([]):
        files = {filename: None for filename in files}

    for filename, sha256 in files.items():
        # Need a repo for each file because repository_ctx.download is blocking. Defining multiple
        # repos allows downloading in parallel.
        _download_artifact_repo(
            name = prefix + "_" + sanitize_repo_name(filename),
            prefix = prefix,
            build_number = build_number,
            target = target,
            downloaded_file_path = filename,
            sha256 = sha256,
        )
