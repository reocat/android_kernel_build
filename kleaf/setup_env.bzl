_CAPTURED_ENV_VARS = [
    "BUILD_CONFIG",
]

def _setup_env_impl(rctx):
    env_vars = {}
    for env_var in _CAPTURED_ENV_VARS:
        env_value = rctx.os.environ.get(env_var)
        env_vars[env_var] = env_value

    rctx.file("BUILD.bazel", """
exports_files(["env.bzl"])
""")

    # Re-export captured environment variables in a .bzl file.
    rctx.file("env.bzl", "\n".join([
        item[0] + " = \"" + str(item[1]) + "\""
        for item in env_vars.items()
    ]))

_setup_env = repository_rule(
    implementation = _setup_env_impl,
    configure = True,
    environ = _CAPTURED_ENV_VARS,
    doc = "A repository rule to capture environment variables.",
)

def setup_env():
    _setup_env(name = "setup_env")
