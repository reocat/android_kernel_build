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

"""Repository for kernel prebuilts."""

load(
    ":constants.bzl",
    "MODULE_OUTS_FILE_SUFFIX",
    "TOOLCHAIN_VERSION_FILENAME",
)
load(
    ":kernel_prebuilt_utils.bzl",
    "CI_TARGET_MAPPING",
    "get_prebuilt_build_file_fragment",
)

visibility("//build/kernel/kleaf/...")

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
    key=value[,key=value,...]
    ```

    Return a list of values, where key matches `expected_key`. If there
    are multiple matches, the first one is returned. If there is no match,
    return `None`.

    For example:
    ```
    MYVAR="myrepo=x,myrepo2=y" bazel ...
    ```

    Then `_parse_env(repository_ctx, "MYVAR", "myrepo")` returns `"x"`
    """
    for pair in repository_ctx.os.environ.get(var_name, "").split(","):
        pair = pair.strip()
        if not pair:
            continue

        tup = pair.split("=", 1)
        if len(tup) != 2:
            fail("Unrecognized token in {}, must be key=value:\n{}".format(var_name, pair))
        key, value = tup
        if key == expected_key:
            return value
    return None

_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{filename}/url?redirect=true"

def _download_artifact_repo_impl(repository_ctx):
    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file, executable = False)

    build_number = _get_build_number(repository_ctx)
    if not build_number:
        _handle_no_build_number(repository_ctx)
    else:
        _download_from_build_number(repository_ctx, build_number)

def _get_build_number(repository_ctx):
    """Gets the value of build number, setting defaults if necessary."""
    build_number = _parse_env(repository_ctx, _BUILD_NUM_ENV_VAR, repository_ctx.attr.parent_repo)
    if not build_number:
        build_number = repository_ctx.attr.build_number
    return build_number

def _handle_no_build_number(repository_ctx):
    """Handles the case where the build number cannot be found."""

    SAMPLE_BUILD_NUMBER = "8077484"
    if repository_ctx.attr.parent_repo == "gki_prebuilts":
        msg = """
ERROR: {parent_repo}: No build_number specified. Fix by specifying `--use_prebuilt_gki=<build_number>"`, e.g.
    bazel build --use_prebuilt_gki={build_number} @{parent_repo}//{filename}
""".format(
            filename = repository_ctx.attr.filename,
            parent_repo = repository_ctx.attr.parent_repo,
            build_number = SAMPLE_BUILD_NUMBER,
        )

    else:
        msg = """
ERROR: {parent_repo}: No build_number specified.

Fix by one of the following:
- Specify `build_number` attribute in {parent_repo}
- Specify `--action_env={build_num_var}="{parent_repo}=<build_number>"`, e.g.
    bazel build \\
      --action_env={build_num_var}="{parent_repo}={build_number}" \\
      @{parent_repo}//{filename}
""".format(
            filename = repository_ctx.attr.filename,
            parent_repo = repository_ctx.attr.parent_repo,
            build_number = SAMPLE_BUILD_NUMBER,
            build_num_var = _BUILD_NUM_ENV_VAR,
        )
    build_file = """
load("{fail_bzl}", "fail_rule")

fail_rule(
    name = "file",
    message = \"\"\"{msg}\"\"\"
)
""".format(
        fail_bzl = Label(":fail.bzl"),
        msg = msg,
    )

    repository_ctx.file("file/BUILD.bazel", build_file, executable = False)

def _download_from_build_number(repository_ctx, build_number):
    local_filename = repository_ctx.attr.local_filename
    remote_filename = repository_ctx.attr.remote_filename_fmt.format(
        build_number = build_number,
    )

    # If there's a "/" in the remote filename, escape
    remote_filename = remote_filename.replace("/", "%2F")

    # Download the requested file
    urls = [repository_ctx.attr.artifact_url_fmt.format(
        build_number = build_number,
        target = repository_ctx.attr.target,
        filename = remote_filename,
    )]
    download_path = repository_ctx.path("file/{}".format(local_filename))
    download_info = repository_ctx.download(
        url = urls,
        output = download_path,
        allow_fail = repository_ctx.attr.allow_fail,
    )

    # Define the filegroup to contain the file.
    # If failing and it is allowed, set filegroup to empty
    if not download_info.success and repository_ctx.attr.allow_fail:
        srcs = ""
    else:
        srcs = '"{}"'.format(local_filename)

    build_file = """filegroup(
    name="file",
    srcs=[{srcs}],
    visibility=["@{parent_repo}//:__pkg__"],
)
""".format(
        srcs = srcs,
        local_filename = local_filename,
        parent_repo = repository_ctx.attr.parent_repo,
    )
    repository_ctx.file("file/BUILD.bazel", build_file, executable = False)

_download_artifact_repo = repository_rule(
    implementation = _download_artifact_repo_impl,
    attrs = {
        "build_number": attr.string(
            doc = "the default build number to use if the environment variable is not set.",
        ),
        "parent_repo": attr.string(doc = "Name of the parent `download_artifacts_repo`"),
        "local_filename": attr.string(
            doc = "Filename and target name used locally to refer to the file.",
        ),
        "remote_filename_fmt": attr.string(
            doc = """Format string of the filename on the download location..

            The filename is determined by `remote_filename_fmt.format(...)`, with the following keys:

            - `build_number`: the environment variable or the `build_number` attribute
            """,
        ),
        "target": attr.string(doc = "Name of target on the download location, e.g. `kernel_aarch64`"),
        "allow_fail": attr.bool(),
        "artifact_url_fmt": attr.string(
            doc = """API endpoint for Android CI artifacts.

            The format may include anchors for the following properties:
                * {build_number}
                * {target}
                * {filename}

            Its default value is the API endpoint for http://ci.android.com.
            """,
            default = _ARTIFACT_URL_FMT,
        ),
    },
    environ = [
        _BUILD_NUM_ENV_VAR,
    ],
)

# buildifier: disable=name-conventions
_FileMetadata = provider(
    "metadata for a downloaded artifact",
    fields = {
        "remote_filename_fmt": """Format string of the filename on the download location..

            The filename is determined by `remote_filename_fmt.format(...)`, with the following keys:

            - `build_number`: the environment variable or the `build_number` attribute
            """,
        "mandatory": "Whether the file must exist",
    },
)

def kernel_prebuilt_repo(
        name,
        artifact_url_fmt,
        build_number = None):
    """Define a repository that downloads kernel prebuilts.

    Args:
        name: name of repository
        artifact_url_fmt: see [`define_kleaf_workspace.artifact_url_fmt`](#define_kleaf_workspace-artifact_url_fmt)
        build_number: build number on [ci.android.com](http://ci.android.com)
    """
    mapping = CI_TARGET_MAPPING[name]
    target = mapping["target"]

    files = {
        out: _FileMetadata(remote_filename_fmt = out, mandatory = True)
        for out in mapping["outs"]
    }
    files[mapping["protected_modules"]] = _FileMetadata(
        remote_filename_fmt = mapping["protected_modules"],
        mandatory = False,
    )
    for config in mapping["download_configs"]:
        mandatory = config["mandatory"]
        files |= {
            out: _FileMetadata(remote_filename_fmt = remote_filename_fmt, mandatory = mandatory)
            for out, remote_filename_fmt in config["outs_mapping"].items()
        }

    for local_filename, file_metadata in files.items():
        # Need a repo for each file because repository_ctx.download is blocking. Defining multiple
        # repos allows downloading in parallel.
        # e.g. @gki_prebuilts_vmlinux
        _download_artifact_repo(
            name = name + "_" + _sanitize_repo_name(local_filename),
            parent_repo = name,
            local_filename = local_filename,
            build_number = build_number,
            target = target,
            remote_filename_fmt = file_metadata.remote_filename_fmt,
            allow_fail = not file_metadata.mandatory,
            artifact_url_fmt = artifact_url_fmt,
        )

    aliases = {
        local_filename: "@" + name + "_" + _sanitize_repo_name(local_filename) + "//file"
        for local_filename in files
    }

    _kernel_prebuilt_repo(
        name = name,
        aliases = aliases,
        arch = mapping["arch"],
        target = mapping["target"],
        outs = mapping["outs"],
        protected_modules = mapping["protected_modules"],
        gki_prebuilts_outs = mapping["gki_prebuilts_outs"],
        download_configs = {
            config["target_suffix"]: list(config["outs_mapping"].keys())
            for config in mapping["download_configs"]
        },
    )

def _kernel_prebuilt_repo_impl(repository_ctx):
    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file, executable = False)
    _kernel_prebuilt_repo_top_build_file(repository_ctx)

def _kernel_prebuilt_repo_top_build_file(repository_ctx):
    target = repository_ctx.attr.target

    content = """\
# Generated file. DO NOT EDIT.

\"""Prebuilts for {target}.
\"""

load("{kernel_bzl}", "kernel_filegroup")
load("{gki_artifacts_bzl}", "gki_artifacts_prebuilts")
""".format(
        kernel_bzl = Label("//build/kernel/kleaf:kernel.bzl"),
        gki_artifacts_bzl = Label("//build/kernel/kleaf/impl:gki_artifacts.bzl"),
        target = target,
    )

    # Aliases
    for local_filename, actual in repository_ctx.attr.aliases.items():
        content += """\

alias(
    name="{local_filename}",
    actual="{actual}",
    visibility=["//visibility:private"]
)
""".format(
            local_filename = local_filename,
            actual = actual,
        )
    content += get_prebuilt_build_file_fragment(
        target = target,
        main_target_outs = repository_ctx.attr.outs,
        download_configs = repository_ctx.attr.download_configs,
        gki_prebuilts_outs = repository_ctx.attr.gki_prebuilts_outs,
        arch = repository_ctx.attr.arch,
        protected_modules = repository_ctx.attr.protected_modules,
        # TODO(b/298416462): This should be determined by downloaded artifacts.
        collect_unstripped_modules = True,
        module_outs_file_suffix = MODULE_OUTS_FILE_SUFFIX,
        toolchain_version_filename = TOOLCHAIN_VERSION_FILENAME,
    )
    repository_ctx.file("BUILD.bazel", content, executable = False)

_kernel_prebuilt_repo = repository_rule(
    implementation = _kernel_prebuilt_repo_impl,
    attrs = {
        "aliases": attr.string_dict(doc = """
            - Keys: local filename.
            - Value: label to the actual target.
            """),
        "arch": attr.string(doc = "Architecture associated with this mapping."),
        "target": attr.string(doc = "Bazel target name in common_kernels.bzl"),
        "outs": attr.string_list(doc = "list of outs associated with that target name"),
        "protected_modules": attr.string(),
        "gki_prebuilts_outs": attr.string_list(),
        "download_configs": attr.string_list_dict(doc = """
            key: `target_suffix`. value: `outs` & `outs_mapping`.
        """),
    },
)
