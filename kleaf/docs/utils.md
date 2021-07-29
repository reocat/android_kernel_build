<!-- Generated with Stardoc: http://skydoc.bazel.build -->

<a name="#bool_flag"></a>

## bool_flag

<pre>
bool_flag(<a href="#bool_flag-name">name</a>)
</pre>

A bool-typed build setting that can be set on the command line

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :-------------: | :-------------: | :-------------: | :-------------: | :-------------: |
| name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |


<a name="#BuildSettingInfo"></a>

## BuildSettingInfo

<pre>
BuildSettingInfo(<a href="#BuildSettingInfo-value">value</a>)
</pre>

A singleton provider that contains the raw value of a build setting

**FIELDS**


| Name  | Description |
| :-------------: | :-------------: |
| value |  The value of the build setting in the current configuration. This value may come from the command line or an upstream transition, or else it will be the build setting's default.    |


