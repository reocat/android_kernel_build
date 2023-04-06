# Configuring DDK module

## Kconfig

The `kconfig` attribute points to a `Kconfig` file that allows you to declare
additional `CONFIG_`s for this module, without affecting the main
`kernel_build`.

The format of the file is specified in
[`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
in the kernel source tree.

These `CONFIG_`s are only meaningful in the current module and its dependants.

The final `Kconfig` file seen by a module consists of the following:
- `Kconfig` from `kernel_build`
- `Kconfig`s of its dependencies, if they exist
- `Kconfig` of this module, if it exists.

## defconfig

The `defconfig` attribute defines the actual values of the `CONFIG_`s declared
in `Kconfig`. This feature may be useful when you have multiple device targets
compiling the same module with different `CONFIG_`s.

It is recommended that all `CONFIG_`s in the `defconfig` of the current
module is declared in the `Kconfig` of the current module. Overriding `CONFIG_`s
from `kernel_build` or dependencies is not recommended and may break in the
future, because the module becomes less self-contained.

Implementation detail: The final `.config` file seen by a module consists of the
following. Earlier items have higher priority.
- `defconfig` of this module, if it exists
- `defconfig`s of its dependencies, if they exist
    - Dependencies are traversed in postorder (See
        [Depsets](https://bazel.build/extending/depsets)).
- `DEFCONFIG` of the `kernel_build`.

## Example

```text
# tuna/Kconfig.ext: Kconfig of the kernel_build
config CONFIG_TUNA_LOW_MEM
	bool "Does the device has low memory?"
```

```sh
# tuna/tuna_defconfig: DEFCONFIG of the kernel_build
CONFIG_TUNA_LOW_MEM=y
```

```python
# tuna/BUILD.bazel
kernel_build(
    name = "tuna",
    kconfig_ext = "Kconfig.ext",
    build_config = "build.config.tuna",
    # build.config.tuna Contains variables to merge tuna_defconfig into
    # gki_defconfig
)

kernel_modules_install(
    name = "tuna_modules_install",
    kernel_modules = [
        "//tuna/graphics",
        "//tuna/display",
    ],
)
```

```
# tuna/graphics/Kconfig: Kconfig of the graphics driver
config TUNA_GRAPHICS_DEBUG
	bool "Enable debug options for tuna graphics driver"
```

```sh
# tuna/graphics/defconfig: defconfig of the graphics driver
# CONFIG_TUNA_GRAPHICS_DEBUG is not set
```

```python
# tuna/graphics/BUILD.bazel

ddk_module(
    name = "graphics",
    kernel_build = "//tuna",
    kconfig = "Kconfig",
    defconfig = "defconfig",
    out = "tuna-graphics.ko",
    srcs = ["tuna-graphics.c"],
)
```

```c
// tuna/graphics/tuna-graphics.c
#include <linux/kconfig.h>

#if IS_ENABLED(CONFIG_TUNA_GRAPHICS_DEBUG)
// You may check configs declared in this module
#endif

#if IS_ENABLED(CONFIG_TUNA_LOW_MEM)
// You may check configs declared in kernel_build
#endif
```

```text
# tuna/display/Kconfig: Kconfig of the display driver

config TUNA_HAS_SECONDARY_DISPLAY
	bool "Does the device has a secondary display?"
```

```sh
# tuna/display/defconfig: defconfig of the display driver

CONFIG_TUNA_HAS_SECONDARY_DISPLAY=y
```

```python
# tuna/display/BUILD.bazel

ddk_module(
    name = "display",
    kernel_build = "//tuna",
    kconfig = "Kconfig",
    defconfig = "defconfig",
    deps = ["//tuna/graphics"],
    out = "tuna-display.ko",
    srcs = ["tuna-display.c"],
)
```

```c
// tuna/display/tuna-display.c
#include <linux/kconfig.h>

#if IS_ENABLED(CONFIG_TUNA_HAS_SECONDARY_DISPLAY)
// You may check configs declared in this module
#endif

#if IS_ENABLED(CONFIG_TUNA_GRAPHICS_DEBUG)
// You may check configs declared in dependencies
#endif

#if IS_ENABLED(CONFIG_TUNA_LOW_MEM)
// You may check configs declared in kernel_build
#endif
```
