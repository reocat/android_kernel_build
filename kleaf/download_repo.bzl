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

_BUILD_NUM_ENV_VAR = "KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"

def _sanitize_repo_name(x):
    """Sanitize x so it can be used as a repository name.

    Replacing invalid characters (those not in `[A-Za-z0-9-_.]`) with `_`.
    """
    ret = ""
    for c in x.elems():
        if not c.isalnum() and not c in "-_.":
            c = "_"
        ret += c
    return ret

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
    MYVAR="
        myrepo=file:///x
        myrepo=file:///y
    " bazel ...
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
        if repository_ctx.attr.prefix == "gki_prebuilts":
            fail("""ERROR: {prefix}: No build_number specified. Fix by specifying `--use_prebuilt_gki=<build_number>"`, e.g.
    bazel build --use_prebuilt_gki={build_number} @{prefix}//{filename}
""".format(
                filename = repository_ctx.attr.filename,
                prefix = repository_ctx.attr.prefix,
                build_number = SAMPLE_BUILD_NUMBER,
            ))

        fail("""ERROR: {prefix}: No build_number specified.

Fix by one of the following:
- Specify `build_number` attribute in {prefix}
- Specify `--action_env={build_num_var}="{prefix}=<build_number>"`, e.g.
    bazel build \\
      --action_env={build_num_var}="{prefix}={build_number}" \\
      @{prefix}//{filename}
""".format(
            filename = repository_ctx.attr.filename,
            prefix = repository_ctx.attr.prefix,
            build_number = SAMPLE_BUILD_NUMBER,
            build_num_var = _BUILD_NUM_ENV_VAR,
        ))

    urls = [_ARTIFACT_URL_FMT.format(
        build_number = build_number,
        target = repository_ctx.attr.target,
        filename = repository_ctx.attr.downloaded_file_path,
    )]

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

_download_artifact_repo = repository_rule(
    implementation = _download_artifact_repo_impl,
    attrs = {
        "build_number": attr.string(),
        "prefix": attr.string(),
        "filename": attr.string(),
        "target": attr.string(),
        "downloaded_file_path": attr.string(),
        "sha256": attr.string(default = ""),
    },
    environ = [
        _BUILD_NUM_ENV_VAR,
    ],
)

def _alias_repo_impl(repository_ctx):
    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file)

    for filename, actual in repository_ctx.attr.aliases.items():
        build_file = """alias(name="{filename}", actual="{actual}", visibility=["//visibility:public"])
""".format(filename = filename, actual = actual)
        repository_ctx.file("{}/BUILD.bazel".format(filename), build_file)

_alias_repo = repository_rule(
    implementation = _alias_repo_impl,
    attrs = {
        "aliases": attr.string_dict(),
    },
)

def download_artifacts_repo(
        name,
        target,
        files,
        build_number = None):
    """Create a repository that contains artifacts downloaded from [ci.android.com](http://ci.android.com).

    For each item `file` in `files`, the label `@{name}//{file}` can refer to the downloaded file.

    For example:
    ```
    download_artifacts_repo(
        name = "gki_prebuilts",
        target = "kernel_kleaf",
        build_number = "8077484"
        files = ["vmlinux"],
    )
    ```

    You may refer to the file with the label `@gki_prebuilts//vmlinux`, etc.

    To refer to all downloaded files, you may use `@gki_prebuilts//...`

    You may leave the build_number empty. If so, you must override the build number at build time.
    See below.

    You may override the build number in the command line by specifing the build number via
    `KLEAF_DOWNLOAD_BUILD_NUMBER_MAP`. In the above example, you may override the build number to
    `8078291` with:

    ```
    bazel build \\
        --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER_MAP="gki_prebuilts=8078291" \\
        @gki_prebuilts//vmlinux
    ```

    Args:
        name: name of the repositories created.
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
            name = name + "_" + _sanitize_repo_name(filename),
            prefix = name,
            filename = filename,
            build_number = build_number,
            target = target,
            downloaded_file_path = filename,
            sha256 = sha256,
        )

    _alias_repo(
        name = name,
        aliases = {
            filename: "@" + name + "_" + _sanitize_repo_name(filename) + "//file"
            for filename in files.keys()
        },
    )
