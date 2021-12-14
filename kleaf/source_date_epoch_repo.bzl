def _impl(repository_ctx):
    if repository_ctx.attr.source_date_epoch:
        return repository_ctx.attr.source_date_epoch
    script = repository_ctx.path(repository_ctx.attr.script)
    res = repository_ctx.execute(
        [script],
        timeout = 5,
        environment = repository_ctx.os.environ,
    )
    if res.return_code != 0:
        fail("Failed to execute {}: return code is {}, stderr is {}".format(
            script,
            res.return_code,
            res.stderr,
        ))
    if res.stderr:
        print("Executing {} yields stderr: {}".format(script, res.stderr))
    print("Executing {} yields stdout: {}".format(script, res.stdout))

    source_date_epoch = res.stdout.strip()

    repository_ctx.file("BUILD", "")
    repository_ctx.file("dict.bzl", "SOURCE_DATE_EPOCH=\"{}\"\n".format(source_date_epoch))

    return {"name": repository_ctx.attr.name, "source_date_epoch": source_date_epoch}

_source_date_epoch_repo = repository_rule(
    implementation = _impl,
    local = True,
    environ = ["SOURCE_DATE_EPOOCH"],
    attrs = {
        "source_date_epoch": attr.string(),
        "script": attr.label(
            default = "//build/kleaf:source_date_epoch_all.sh",
            allow_single_file = True,
        ),
    },
)

def source_date_epoch_repo(name):
    _source_date_epoch_repo(
        name = name,
    )
