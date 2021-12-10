#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Generate a DDK module Makefile
"""

import argparse
import sys

def gen_ddk_makefile(output_makefile, configs = (), kernel_module_outs = ()):
    for out in kernel_module_outs:
        if not out.endswith(".ko"):
            raise RuntimeError("Unknown outs in ddk_module, must end with .ko: {}".format(out))
        out = out[:-len(".ko")] + ".o"
        output_makefile.write("obj-m += {}\n".format(out))
    for config in configs:
        tup = config.split(":")
        if not len(tup) >= 2:
            raise RuntimeError("Unknown --configs: {}".format(config))
        name, type = tup[0], tup[1]
        if type == "tristate":
            output_makefile.write("KBUILD_OPTIONS += CONFIG_{}=m\n".format(name))
    output_makefile.write(
"""modules modules_install clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) W=1 $(@)
""")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configs", nargs="*")
    parser.add_argument("--kernel-module-outs", nargs="*")
    parser.add_argument("--output-makefile", type=argparse.FileType('w'),
                        default=sys.stdout)
    gen_ddk_makefile(**vars(parser.parse_args()))
