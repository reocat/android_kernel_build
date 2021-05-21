filegroup(
    name = "kernel-build-scripts",
    srcs = [
        "_setup_env.sh",
        "build.sh",
    ] + glob(
        ["build-tools/**"],
        allow_empty = False,
    ),
    visibility = ["//visibility:public"],
)
