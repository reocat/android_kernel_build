load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")

# Check effect of kbuild_symtypes
def _kbuild_symtypes_test_impl(ctx):
    env = analysistest.begin(ctx)

    return analysistest.end(env)

kbuild_symtypes_test = analysistest.make(_kbuild_symtypes_test_impl)

def _test_kbuild_symtypes(test_suite_name):
    kernel_build(
        name = test_suite_name + "_test_kbuild_symtypes_subject",
        tags = ["manual"],
        # FIXME
    )
    kbuild_symtypes_test(
        name = test_suite_name + "_test_kbuild_symtypes",
    )

def kernel_build_analysis_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _test_kbuild_symtypes(test_suite_name),
        ],
    )
