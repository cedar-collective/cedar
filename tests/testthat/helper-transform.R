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

# The report list parse-data.R reads (R/data-parsers/report-specs.R): the specs
# and the functions that convert an export, read it, find its header and drop
# its footer lines, sourced into their own environment.
load_report_specs <- function() {
  env <- new.env(parent = .GlobalEnv)
  sys.source(file.path(cedar_base_dir, "R/data-parsers/report-specs.R"), envir = env)
  env
}

# A stand-in for xlsx2csv: a script that writes `lines` to the file named by
# its second argument and ends with `status`, as the converter does when it
# stops part-way. It is removed when the calling test ends.
local_report_converter <- function(lines, status = 0L, env = parent.frame()) {
  converter <- withr::local_tempfile(fileext = ".sh", .local_envir = env)
  writeLines(c("#!/bin/sh", "cat > \"$2\" <<'CEDAR_EXPORT'", lines, "CEDAR_EXPORT",
               paste("exit", status)), converter)
  Sys.chmod(converter, "755")
  converter
}
