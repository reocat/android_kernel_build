"""Drop-in replacement for `{new_,}local_repository` such that
    paths are resolved against Kleaf sub-repository."""

def _get_kleaf_repo_dir(repository_ctx):
    mylabel = Label(":local_repository.bzl")
    mypath = str(repository_ctx.path(Label(":local_repository.bzl")))
    package_path = mypath.removesuffix(mylabel.name).removesuffix("/")
    kleaf_repo_dir = package_path.removesuffix(mylabel.package).removesuffix("/")
    return repository_ctx.path(kleaf_repo_dir)

def _kleaf_local_repository_impl(repository_ctx):
    kleaf_repo_dir = _get_kleaf_repo_dir(repository_ctx)

    target = kleaf_repo_dir.get_child(repository_ctx.attr.path)
    for child in target.readdir():
        repository_ctx.symlink(child, repository_ctx.path(child.basename))

kleaf_local_repository = repository_rule(
    attrs = {
        "path": attr.string(doc = "the path relative to Kleaf repository"),
    },
    implementation = _kleaf_local_repository_impl,
)

def _new_kleaf_local_repository_impl(repository_ctx):
    kleaf_repo_dir = _get_kleaf_repo_dir(repository_ctx)

    target = kleaf_repo_dir.get_child(repository_ctx.attr.path)
    for child in target.readdir():
        repository_ctx.symlink(child, repository_ctx.path(child.basename))
    if repository_ctx.attr.build_file:
        repository_ctx.symlink(
            kleaf_repo_dir.get_child(repository_ctx.attr.build_file),
            repository_ctx.path("BUILD.bazel"),
        )
    repository_ctx.file(repository_ctx.path("WORKSPACE.bazel"), """\
workspace({name_repr})
""".format(name_repr = repr(repository_ctx.attr.name)))

new_kleaf_local_repository = repository_rule(
    attrs = {
        "path": attr.string(doc = "the path relative to Kleaf repository"),
        "build_file": attr.string(doc = "build file. Path is calculated with `repository_ctx.path(build_file)`"),
    },
    implementation = _new_kleaf_local_repository_impl,
)
