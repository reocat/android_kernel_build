# BTF debug information

Option `--btf_debug_info` can enable or disable generation of BTF debug
information:

* `default` - use kernel config value for CONFIG_DEBUG_INFO_BTF.
* `enable` - enable generation of BTF debug information.
* `disable` - disable generation of BTF debug information.

While this information is useful for debugging and loading BPF programs, it
requires a lot of time to be generated. Currently, there is no runtime
dependencies on BTF debug information and for the faster local build one can try
`--btf_debug_info=disable` in addition to `--config=fast`. But there is no
guarrantee that future kernels will boot without CONFIG_DEBUG_INFO_BTF.
