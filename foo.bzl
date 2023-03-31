def foo_impl(ctx):
  d = ctx.actions.declare_directory(ctx.attr.name)
  ctx.actions.run_shell(outputs = [d], command = """
    : > {}/a.txt
  """.format(d.path))
  return DefaultInfo(files = depset([d]))
foo = rule(implementation = foo_impl)
