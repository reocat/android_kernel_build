"""repo that helps declaring kernel prebuilts."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "//build/kernel/kleaf/impl:kernel_prebuilt_utils.bzl",
    "CI_TARGET_MAPPING",
    "GKI_DOWNLOAD_CONFIGS",
)

visibility("//build/kernel/kleaf/...")

_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{filename}/url?redirect=true"

def _bool_to_str(b):
    """Turns boolean to string."""

    # We can't use str() because bool(str(False)) != False
    return "True" if b else ""

def _str_to_bool(s):
    """Turns string to boolean."""

    # We can't use bool() because bool(str(False)) != False
    if s == "True":
        return True
    if not s:
        return False
    fail("Invalid value {}".format(s))

def _infer_download_config(target):
    chosen_mapping = None
    for mapping in CI_TARGET_MAPPING.values():
        if mapping["target"] == target:
            chosen_mapping = mapping
    if not chosen_mapping:
        fail("auto_download_config with {} is not supported yet.".format(target))

    download_config = {}
    mandatory = {}

    for out in chosen_mapping["outs"]:
        download_config[out] = out
        mandatory[out] = True

    protected_modules = chosen_mapping["protected_modules"]
    download_config[protected_modules] = protected_modules
    mandatory[protected_modules] = False

    for config in GKI_DOWNLOAD_CONFIGS:
        config_mandatory = config.get("mandatory", True)
        for out in config.get("outs", []):
            download_config[out] = out
            mandatory[out] = config_mandatory
        for out, remote_filename_fmt in config.get("outs_mapping", {}).items():
            download_config[out] = remote_filename_fmt
            mandatory[out] = config_mandatory

    mandatory = {key: _bool_to_str(value) for key, value in mandatory.items()}

    return download_config, mandatory

def _kernel_prebuilt_repo_new_impl(repository_ctx):
    download_config = repository_ctx.attr.download_config
    mandatory = repository_ctx.attr.mandatory
    if repository_ctx.attr.auto_download_config:
        if download_config:
            fail("{}: download_config should not be set when auto_download_config is True".format(repository_ctx.attr.name))
        if mandatory:
            fail("{}: mandatory should not be set when auto_download_config is True".format(repository_ctx.attr.name))
        download_config, mandatory = _infer_download_config(repository_ctx.attr.target)

    futures = []

    for local_filename, remote_filename_fmt in download_config.items():
        local_path = repository_ctx.path(paths.join(local_filename, paths.basename(local_filename)))
        remote_filename = remote_filename_fmt.format(
            build_number = repository_ctx.attr.build_number,
            target = repository_ctx.attr.target,
        )
        file_mandatory = _str_to_bool(mandatory.get(local_filename, _bool_to_str(True)))

        if repository_ctx.attr.local_artifact_path:
            artifact_path = repository_ctx.workspace_root.get_child(repository_ctx.attr.local_artifact_path).get_child(remote_filename)
            if artifact_path.exists:
                repository_ctx.symlink(artifact_path, local_path)
            elif file_mandatory:
                fail("{}: {} does not exist".format(repository_ctx.attr.name, artifact_path))
        else:
            artifact_url = repository_ctx.attr.artifact_url_fmt.format(
                build_number = repository_ctx.attr.build_number,
                target = repository_ctx.attr.target,
                filename = remote_filename,
            )
            future = repository_ctx.download(
                url = artifact_url,
                output = local_path,
                allow_fail = not file_mandatory,
                # TODO(b/325494748): With bazel 7.1.0, use parallel download
                # block = False, # TODO bazel 7.1.0
            )
            futures.append(future)

        # FIXME: This should be an empty filegroup if no such file & not mandatory
        repository_ctx.file(paths.join(local_filename, "BUILD.bazel"), """\
exports_files(
    [{}],
    visibility = ["//visibility:public"],
)""".format(repr(paths.basename(local_filename))))

    # TODO(b/325494748): With bazel 7.1.0, use parallel download
    # for future in futures:
    #     future.wait()

    repository_ctx.file("""WORKSPACE.bazel""", """\
workspace({})
""".format(repr(repository_ctx.attr.name)))

_kernel_prebuilt_repo_new = repository_rule(
    implementation = _kernel_prebuilt_repo_new_impl,
    attrs = {
        "artifact_url_fmt": attr.string(),
        "local_artifact_path": attr.string(),
        "build_number": attr.string(),
        "auto_download_config": attr.bool(),
        "download_config": attr.string_dict(),
        "mandatory": attr.string_dict(),
        "target": attr.string(),
    },
)

_tag_class = tag_class(
    doc = "Declares a repo that contains kernel prebuilts",
    attrs = {
        "name": attr.string(
            doc = "name of repository",
            mandatory = True,
        ),
        "artifact_url_fmt": attr.string(
            doc = """API endpoint for Android CI artifacts.

                The format may include anchors for the following properties:
                    * {build_number}
                    * {target}
                    * {filename}

                Its default value is the API endpoint for http://ci.android.com.""",
            default = _ARTIFACT_URL_FMT,
        ),
        "local_artifact_path": attr.string(
            doc = """Directory to local artifacts.

                If set, `artifact_url_fmt` is ignored.

                Only the root module may call `declare()` with this attribute set.

                If relative, it is interpreted against workspace root.
            """,
        ),
        "build_number": attr.string(
            doc = """build number to be used in `artifact_url_fmt`.

                Unlike `kernel_prebuilt_repo`, the environment variable
                `KLEAF_DOWNLOAD_BUILD_NUMBER_MAP` is **NOT** respected.
            """,
        ),
        "auto_download_config": attr.bool(
            doc = """If `True`, infer `download_config` and `mandatory`
                from `target`.""",
        ),
        "download_config": attr.string_dict(
            doc = """Configure the list of files to download.

                Key: local file name.

                Value: remote file name format string, with the following anchors:
                    * {build_number}
                    * {target}
            """,
        ),
        "mandatory": attr.string_dict(
            doc = """Configure whether files are mandatory.

                Key: local file name.

                Value: Whether the file is mandatory.

                If a file name is not found in the dictionary, default
                value is `True`. If mandatory, failure to download the
                file results in a build failure.
            """,
        ),
        "target": attr.string(
            doc = """Name of the build target as identified by the remote build server.

                This attribute has two effects:

                * Replaces the `{target}` anchor in `artifact_url_fmt`.
                    If `artifact_url_fmt` does not have the `{target}` anchor,
                    this has no effect.

                * If `auto_download_config` is `True`, `download_config`
                    and `mandatory` is inferred from a
                    list of known configs keyed on `target`.
            """,
            default = "kernel_aarch64",
        ),
    },
)

def _declare_repos(module_ctx, tag_name):
    for module in module_ctx.modules:
        for module_tag in getattr(module.tags, tag_name):
            _kernel_prebuilt_repo_new(
                name = module_tag.name,
                artifact_url_fmt = module_tag.artifact_url_fmt,
                local_artifact_path = module_tag.local_artifact_path,
                build_number = module_tag.build_number,
                auto_download_config = module_tag.auto_download_config,
                download_config = module_tag.download_config,
                mandatory = module_tag.mandatory,
                target = module_tag.target,
            )

kernel_prebuilt_repo_new = struct(
    declare_repos = _declare_repos,
    tag_class = _tag_class,
)
