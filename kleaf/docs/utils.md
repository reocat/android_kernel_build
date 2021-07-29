<!-- Generated with Stardoc: http://skydoc.bazel.build -->

<a name="#bool_flag"></a>

## bool_flag

<pre>
bool_flag(<a href="#bool_flag-name">name</a>)
</pre>

A bool-typed build setting that can be set on the command line

### Attributes


#### name <a name="bool_flag-name"></a> {:#bool_flag-name}

*<a href="https://bazel.build/docs/build-ref.html#name">Name</a>.*  *Required.*   A unique name for this target.



<a name="#string_flag"></a>

## string_flag

<pre>
string_flag(<a href="#string_flag-name">name</a>, <a href="#string_flag-values">values</a>)
</pre>

A string-typed build setting that can be set on the command line

### Attributes


#### name <a name="string_flag-name"></a> {:#string_flag-name}

*<a href="https://bazel.build/docs/build-ref.html#name">Name</a>.*  *Required.*   A unique name for this target.

#### values <a name="string_flag-values"></a> {:#string_flag-values}

*List of strings.*  *Optional.*   *Default is* `[]`.  The list of allowed values for this setting. An error is raised if any other value is given.



<a name="#BuildSettingInfo"></a>

## BuildSettingInfo

<pre>
BuildSettingInfo(<a href="#BuildSettingInfo-value">value</a>)
</pre>

A singleton provider that contains the raw value of a build setting

### Fields


#### value value <a name="BuildSettingInfo-value"></a> {:#BuildSettingInfo-value}

The value of the build setting in the current configuration. This value may come from the command line or an upstream transition, or else it will be the build setting's default.



