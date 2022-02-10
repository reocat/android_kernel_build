def _copy_file(repository_ctx, src, dst):
    content = repository_ctx.read(src)
    repository_ctx.file(dst, content)

def _move_file(repository_ctx, src, dst):
    _copy_file(repository_ctx, src, dst)
    repository_ctx.delete(src)

def _impl(repository_ctx):
    setlocalversion = repository_ctx.path(repository_ctx.attr.setlocalversion)
    wd = setlocalversion.dirname.dirname
    args = [
        str(setlocalversion.realpath),
        "--save-scmversion",
    ]
    result = repository_ctx.execute(args, working_directory = str(wd))
    if result.return_code != 0:
        fail("Unable to execute {command} (wd: {wd})".format(
            command = " ".join(args),
            wd = wd,
        ))

    _move_file(repository_ctx, wd.get_child(".scmversion"), "file/scmversion")

    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")
""".format(repository_ctx.name))

    repository_ctx.file("file/BUILD.bazel", """filegroup(
    name = "file",
    srcs = ["scmversion"],
)
""")

_scmversion_repo = repository_rule(
    implementation = _impl,
    local = True,
    attrs = {
        "setlocalversion": attr.label(doc = "Location of the `setlocalversion` script."),
        "git_head": attr.label(doc = "Location of the `.git/HEAD` to monitor changes of the resulting `.scmversion`"),
    },
)

def scmversion_repo(
        name,
        kernel_dir):
    """Define a repository that determines the value of `.scmversion`.

Example:

```
scmversion_repo(
    name = "scmversion",
    kernel_dir = "//.source_date_epoch_dir"
)
```

    Args:
        name: Name of the repository.
        kernel_dir: Name of package of at `$KERNEL_DIR`.
    """

    _scmversion_repo(
        name = name,
        setlocalversion = kernel_dir + ":scripts/setlocalversion",
        git_head = kernel_dir + ":.git/HEAD",
    )
