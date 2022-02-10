def _impl(repository_ctx):
    # Set up a fake working directory for setlocalversion to execute on.
    repository_ctx.file("working_dir/include/config/auto.conf", """CONFIG_LOCALVERSION_AUTO=y
""")
    wd = repository_ctx.path("working_dir")
    setlocalversion = repository_ctx.path(repository_ctx.attr.setlocalversion)
    kernel_dir = setlocalversion.dirname.dirname

    # cd working_dir && setlocalversion $KERNEL_DIR
    args = [
        str(setlocalversion.realpath),
        str(kernel_dir),  # srctree
    ]
    result = repository_ctx.execute(args, working_directory = str(wd))
    if result.return_code != 0:
        fail("Unable to execute {command} (working dir: {wd})".format(
            command = " ".join(args),
            wd = wd,
        ))

    repository_ctx.file("file/scmversion", result.stdout)

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
        "deps": attr.label_list(doc = "Location of interesting files to monitor changes of the resulting `.scmversion`"),
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
        deps = [
            # Note: If the git source tree is dirty, checking just .git/HEAD may update scmversion
            # to append "-dirty" to the scmversion file we are creating. However, this is a
            # limitation we cannot overcome due to the lack of glob() at workspace time.
            kernel_dir + ":.git/HEAD",
        ],
    )
