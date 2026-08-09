# cedar-repl.R - bootstrap for interactive analysis against local CEDAR data.
#
#   Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_students)'
#
# Run from the repository root and always with --vanilla. This is an analysis
# helper, not a test runner, and its output is never release evidence.

suppressMessages({
  library(dplyr)
  library(tibble)
  library(qs2)
})

.cedar_root <- local({
  d <- getwd()
  while (!file.exists(file.path(d, "global.R")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "global.R"))) {
    stop("[cedar-repl.R] Could not find the CEDAR repo root from ", getwd())
  }
  d
})

cedar_base_dir <<- .cedar_root
cedar_data_dir <<- file.path(.cedar_root, "data")

source(file.path(.cedar_root, "R", "trunk", "load-funcs.R"))
load_funcs(cedar_base_dir = .cedar_root, modules = FALSE)

# Load a local CEDAR table by name, e.g. cedar_read("cedar_students").
cedar_read <- function(name) {
  path <- file.path(cedar_data_dir, paste0(name, ".qs"))
  if (!file.exists(path)) stop("[cedar-repl.R] No such data file: ", path)
  qs2::qs_read(path)
}

# Tables load lazily so sourcing remains fast when only one is needed.
for (.nm in c("cedar_students", "cedar_programs", "cedar_degrees",
              "cedar_sections", "cedar_grades", "cedar_student_term_credits",
              "cedar_applicants", "cedar_lookups")) {
  local({
    name <- .nm
    if (file.exists(file.path(cedar_data_dir, paste0(name, ".qs")))) {
      delayedAssign(name, cedar_read(name), assign.env = .GlobalEnv)
    }
  })
}
rm(.nm)

message("[cedar-repl.R] Ready. Tables load on first use; cedar_read(\"<name>\") for others.")
