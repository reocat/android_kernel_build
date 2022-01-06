sign_module_deps = [
    # Kernel build time module signining utility and keys
    # Only available if build_config has CONFIG_MODULE_SIG=y and
    # CONFIG_MODULE_SIG_PROTECT=y
    # android13-5.10+ and android-mainline
    "scripts/sign-file",
    "certs/signing_key.pem",
    "certs/signing_key.x509",
]
