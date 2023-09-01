load("//build/kernel/kleaf/impl:utils.bzl", "utils")

def _zip_archive_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.zip_file)
    depset_written = utils.write_depset(ctx, depset(ctx.files.srcs), "zip_depset.txt")

    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [out],
        executable = ctx.executable._zipper,
        arguments = ["-o", out.path, "-l", depset_written.depset_file.path],
        mnemonic = "Zip",
        progress_message = "Generating %s" % (
            ctx.attr.zip_file
        ),
    )
    return [DefaultInfo(files = depset([out, depset_written.depset_file]))]

zip_archive = rule(
    implementation = _zip_archive_impl,
    attrs = {
        "srcs": attr.label_list(mandatory = True, allow_files = True),
        "zip_file": attr.string(mandatory = True),
        "_write_depset": attr.label(
            default = "//build/kernel/kleaf/impl:write_depset",
            executable = True,
            cfg = "exec",
        ),
        "_zipper": attr.label(
            default = "//prebuilts/build-tools:linux-x86/bin/soong_zip",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
