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

    kernel_build = ctx.attr.kernel_modules_install[KernelModuleInfo].kernel_build
    if KernelImagesInfo in kernel_build and kernel_build[KernelImagesInfo].images != None:
        # Build device-specific system_dlkm against GKI's system_dlkm_staging_archive.tar.gz
        source_staging_archive = utils.find_file(
            name = _STAGING_ARCHIVE_NAME,
            files = kernel_build[KernelImagesInfo].images.files.to_list(),
            what = "{} (images for {})".format(kernel_build[KernelImagesInfo].images.label, ctx.label),
            required = True,
        )
        additional_inputs.append(source_staging_archive)

        # TODO dedup with build_utils.sh
        command = """
                # Copy staging archive
                  cp -pl {source_staging_archive} {system_dlkm_staging_archive}

                # Extract staging archive
                  mkdir -p {system_dlkm_staging_dir}
                  tar xf {source_staging_archive} -C {system_dlkm_staging_dir}

                # Copy modules.load
                  local system_dlkm_root_dir=$(echo ${system_dlkm_staging_dir}/lib/modules/*)
                  cp ${{system_dlkm_root_dir}}/modules.load {system_dlkm_modules_load}

                # Build system_dlkm.img
                  local system_dlkm_props_file
                  system_dlkm_props_file=$(build_system_dlkm_props) || exit 1

                  build_image "{system_dlkm_staging_dir}" "${{system_dlkm_props_file}}" \
                    "{system_dlkm_img}" /dev/null

                # No need to sign the image as modules are signed
                  avbtool add_hashtree_footer \
                    --partition_name system_dlkm \
                    --image "{system_dlkm_img}"
        """.format(
            source_staging_archive = source_staging_archive.path,
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
    }),
)
