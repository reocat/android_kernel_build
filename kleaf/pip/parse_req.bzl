load("@rules_python//python:pip.bzl", "pip_parse")

def parse_req():
    pip_parse(
        name = "pypi",
        requirements_lock = "//build/kernel/kleaf/pip:requirements_lock.txt",
    )