# What the tests in test-r-environment.R share: builders, option lists, constants.

# scripts/r-environment.R is a script, not a sourced layer: load_funcs() never
# reads it. Its functions are read into an environment of their own, as
# load_transform_helpers() reads the transform's. Sourcing it changes nothing,
# which the first test in test-r-environment.R holds it to.
load_r_environment_script <- function() {
  env <- new.env(parent = globalenv())
  sys.source(file.path(cedar_base_dir, "scripts", "r-environment.R"), envir = env)
  env
}
