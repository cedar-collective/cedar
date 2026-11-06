# The transform (R/data-parsers/transform-to-cedar.R) is a script, not a
# sourced layer: load_funcs() never reads it. Tests that run a stage of it, or
# the staleness check the deploy gate asks, source it into its own
# environment here, from the repository root as the script expects.
load_transform_helpers <- function() {
  env <- new.env(parent = .GlobalEnv)
  env$SOURCED_FROM_PARSE_DATA <- TRUE
  old_wd <- getwd()
  setwd(cedar_base_dir)
  on.exit(setwd(old_wd), add = TRUE)
  sys.source(file.path(cedar_base_dir, "R/data-parsers/transform-to-cedar.R"),
             envir = env)
  env
}
