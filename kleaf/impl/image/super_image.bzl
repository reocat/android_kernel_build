""" Builds super.img """
load(":common_providers.bzl", "KernelEnvInfo")
load(":debug.bzl", "debug")

visibility("//build/kernel/kleaf/...")

def _super_image_impl(ctx):
    inputs = []
    inputs += ctx.files.system_dlkm_image
    inputs += ctx.files.vendor_dlkm_image

    transitive_inputs = [ctx.attr.env[KernelEnvInfo].inputs]
    tools = ctx.attr.env[KernelEnvInfo].tools

    super_img = ctx.actions.declare_file("{}/super.img".format(ctx.label.name))
    super_img_size = ctx.attr.super_img_size
    super_unsparsed_img = ctx.actions.declare_file("{}/super_unsparsed.img".format(ctx.label.name))

    outputs = [super_img, super_unsparsed_img]

    # Create a bash array of input images
    super_img_contents = "("
    for dep in [ctx.attr.system_dlkm_image, ctx.attr.vendor_dlkm_image]:
        for f in dep.files.to_list():
            if f.extension == "img":
                super_img_contents += f.path + " "
    super_img_contents += ")"

    command = ctx.attr.env[KernelEnvInfo].setup + """
            # Build super
              mkdir -p "$DIST_DIR"
              (
                SUPER_IMAGE_CONTENTS={super_img_contents}
                SUPER_IMAGE_SIZE={super_img_size}
                build_super
              )
            # Move output files into place
              mv "${{DIST_DIR}}/super.img" {super_img}
              mv "${{DIST_DIR}}/super_unsparsed.img" {super_unsparsed_img}
    """.format(
        super_img = super_img.path,
        super_img_size = super_img_size,
        super_unsparsed_img = super_unsparsed_img.path,
        super_img_contents = super_img_contents,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "SuperImage",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = outputs,
        tools = tools,
        progress_message = "Building super image %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
        ),
    ]

super_image = rule(
    implementation = _super_image_impl,
    doc = """Build super image.

Execute `build_super` in `build_utils.sh`.

Takes in a system_dlkm and vendor_dlkm.

When included in a `copy_to_dist_dir` rule, this rule copies a `super.img` to `DIST_DIR`.
""",
    attrs = {
        "system_dlkm_image": attr.label(
            mandatory = True,
            doc = "`system_dlkm_image` to include in super.img",
        ),
        "vendor_dlkm_image": attr.label(
            mandatory = True,
            doc = "`vendor_dlkm_image` to include in super.img",
        ),
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "`kernel_env` to source build utilities from",
        ),
        "super_img_size": attr.int(
            default = 0x10000000,
            doc = "Size of super.img",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
