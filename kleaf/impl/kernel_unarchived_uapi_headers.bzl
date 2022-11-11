def _kernel_unarchived_uapi_headers_impl(ctx):
    input_tar = ctx.file.kernel_uapi_headers
    out_dir = ctx.actions.declare_directory(ctx.label.name)

    ctx.actions.run_shell(
        mnemonic = "KernelUnarchivedUapiHeaders",
        inputs = [input_tar],
        outputs = [out_dir],
        progress_message = "Unpacking UAPI headers",
        arguments = [input_tar.path, out_dir.path],
        command = """
          # Process args
          tar_file="${PWD}/$1"
          out_dir="${PWD}/$2"
          # Make output dir and switch to it
          mkdir -p "$out_dir" && cd "$out_dir"
          # Unpack headers (stripping /usr/include)
          tar --strip-components=2 -xzf "$tar_file"
        """,
    )

    return [
        DefaultInfo(files = depset([out_dir])),
    ]

kernel_unarchived_uapi_headers = rule(
    implementation = _kernel_unarchived_uapi_headers_impl,
    doc = """Unpack `kernel-uapi-headers.tar.gz`""",
    attrs = {
        "kernel_uapi_headers": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "the kernel_uapi_headers tarball or label",
        ),
    },
)
