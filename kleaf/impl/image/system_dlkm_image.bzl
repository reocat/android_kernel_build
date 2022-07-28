# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load(":debug.bzl", "debug")
load(":image/image_utils.bzl", "image_utils")
load(
    ":common_providers.bzl",
    "KernelImagesInfo",
    "KernelModuleInfo",
)

_STAGING_ARCHIVE_NAME = "system_dlkm_staging_archive.tar.gz"

def _system_dlkm_image_impl(ctx):
    system_dlkm_img = ctx.actions.declare_file("{}/system_dlkm.img".format(ctx.label.name))
    system_dlkm_modules_load = ctx.actions.declare_file("{}/system_dlkm.modules.load".format(ctx.label.name))
    system_dlkm_staging_archive = ctx.actions.declare_file("{}/{}".format(ctx.label.name, _STAGING_ARCHIVE_NAME))

    modules_staging_dir = system_dlkm_img.dirname + "/staging"
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    additional_inputs = []
    building_device_system_dlkm = False

    kernel_build = ctx.attr.kernel_modules_install[KernelModuleInfo].kernel_build
    if KernelImagesInfo in kernel_build and kernel_build[KernelImagesInfo].images != None:
        # Build device-specific system_dlkm against GKI's system_dlkm_staging_archive.tar.gz
        building_device_system_dlkm = True
        source_staging_archive = utils.find_file(
            name = _STAGING_ARCHIVE_NAME,
            files = kernel_build[KernelImagesInfo].images.files.to_list(),
            what = "{} (images for {})".format(kernel_build[KernelImagesInfo].images.label, ctx.label),
            required = True,
        )
        additional_inputs.append(source_staging_archive)

        # FIXME dedup with below
        command = """
                # Extract staging archive
                  mkdir -p {system_dlkm_staging_dir}
                  tar xf {source_staging_archive} -C {modules_staging_dir}

                # Build system_dlkm.img
                  mkdir -p {system_dlkm_staging_dir}
                  (
                       MODULES_STAGING_DIR={modules_staging_dir}
                       SYSTEM_DLKM_STAGING_DIR={system_dlkm_staging_dir}
                     # Trick create_modules_staging to not strip, because they are already stripped and signed
                       DO_NOT_STRIP_MODULES=
                     # Trick create_modules_staging to not look at external modules. They aren't related.
                       EXT_MODULES=
                       EXT_MODULES_MAKEFILE=
                     # Tell build_system_dlkm to not sign, because they are already signed
                       SYSTEM_DLKM_RE_SIGN=0
                       build_system_dlkm
                   )
                 # Move output files into place
                   mv "${{DIST_DIR}}/system_dlkm.img" {system_dlkm_img}
                   mv "${{DIST_DIR}}/system_dlkm.modules.load" {system_dlkm_modules_load}
                   mv "${{DIST_DIR}}/system_dlkm_staging_archive.tar.gz" {system_dlkm_staging_archive}

                 # Remove staging directories
                   rm -rf {system_dlkm_staging_dir}
        """.format(
            source_staging_archive = source_staging_archive.path,
            modules_staging_dir = modules_staging_dir,
            system_dlkm_staging_dir = system_dlkm_staging_dir,
            system_dlkm_img = system_dlkm_img.path,
            system_dlkm_modules_load = system_dlkm_modules_load.path,
            system_dlkm_staging_archive = system_dlkm_staging_archive.path,
        )
    else:
        command = """
                 # Build system_dlkm.img
                   mkdir -p {system_dlkm_staging_dir}
                   (
                     MODULES_STAGING_DIR={modules_staging_dir}
                     SYSTEM_DLKM_STAGING_DIR={system_dlkm_staging_dir}
                     build_system_dlkm
                   )
                 # Move output files into place
                   mv "${{DIST_DIR}}/system_dlkm.img" {system_dlkm_img}
                   mv "${{DIST_DIR}}/system_dlkm.modules.load" {system_dlkm_modules_load}
                   mv "${{DIST_DIR}}/system_dlkm_staging_archive.tar.gz" {system_dlkm_staging_archive}

                 # Remove staging directories
                   rm -rf {system_dlkm_staging_dir}
        """.format(
            modules_staging_dir = modules_staging_dir,
            system_dlkm_staging_dir = system_dlkm_staging_dir,
            system_dlkm_img = system_dlkm_img.path,
            system_dlkm_modules_load = system_dlkm_modules_load.path,
            system_dlkm_staging_archive = system_dlkm_staging_archive.path,
        )

    default_info = image_utils.build_modules_image_impl_common(
        ctx = ctx,
        what = "system_dlkm",
        # Sync with GKI_DOWNLOAD_CONFIGS, "images"
        outputs = [
            system_dlkm_img,
            system_dlkm_modules_load,
            system_dlkm_staging_archive,
        ],
        additional_inputs = additional_inputs,
        building_device_system_dlkm = building_device_system_dlkm,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        mnemonic = "SystemDlkmImage",
    )
    return [default_info]

system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm.img an erofs image with GKI modules.

When included in a `copy_to_dist_dir` rule, this rule copies the following to `DIST_DIR`:
- `system_dlkm.img`
- `system_dlkm.modules.load`

""",
    attrs = image_utils.build_modules_image_attrs_common({
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
        "system_dlkm_modules_list": attr.label(allow_single_file = True),
        "system_dlkm_modules_blocklist": attr.label(allow_single_file = True),
        "system_dlkm_props": attr.label(allow_single_file = True),
    }),
)
