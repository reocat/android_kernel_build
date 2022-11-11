load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")

def _kernel_unarchived_uapi_headers_impl(ctx):
    input_tar = ctx.file.kernel_uapi_headers
    out_dir = ctx.actions.declare_directory(ctx.label.name)

    inputs = [input_tar]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    command = ""
    command += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    command += """
      # Create output dir
      mkdir -p "{out_dir}"
      # Unpack headers (stripping /usr/include)
      tar --strip-components=2 -C "{out_dir}" -xzf "{tar_file}"
    """.format(
        tar_file = input_tar.path,
        out_dir = out_dir.path,
    )

    ctx.actions.run_shell(
        mnemonic = "KernelUnarchivedUapiHeaders",
        inputs = inputs,
        outputs = [out_dir],
        progress_message = "Unpacking UAPI headers {}".format(ctx.label),
        command = command,
    )

    return [
        DefaultInfo(files = depset([out_dir])),
    ]

kernel_unarchived_uapi_headers = rule(
    implementation = _kernel_unarchived_uapi_headers_impl,
    doc = """Unpack `kernel-uapi-headers.tar.gz` (stripping usr/include)""",
    attrs = {
        "kernel_uapi_headers": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "the kernel_uapi_headers tarball or label",
        ),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
    },
)
