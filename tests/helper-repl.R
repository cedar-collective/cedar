# helper-repl.R — one-line bootstrap for ad-hoc analysis against real data.
#
#   Rscript --vanilla -e 'source("tests/helper-repl.R"); nrow(cedar_students)'
#
# Run it from the REPO ROOT, and always with --vanilla (see AGENTS.md →
# Running tests). Without --vanilla, .Rprofile activates renv.
#
# WHY THIS EXISTS
#
# Every throwaway script that wanted to check something against the real tables
# rediscovered the same obstacles, in the same order, costing a debugging round
# each time:
#
#   1. The data files are qs2, not qs. `qs::qread()` fails with the unhelpful
#      "QS format not detected".            -> use qs2::qs_read()
#   2. load_funcs() takes cedar_base_dir as a required argument with no default.
#   3. ...and then dies on a missing `cedar_data_dir` global, which nothing
#      documents and which only the test helper sets.
#
# NOT on that list: renv. With --vanilla there is no renv to fight. Never call
# renv::deactivate() to "fix" a library error — it rewrites .Rprofile as a side
# effect, and a session that did so silently disabled renv activation for the
# whole project and committed the change.

suppressMessages({
  library(dplyr)
  library(tibble)
  library(qs2)
})

# Repo root, whether sourced from the root or from tests/.
.cedar_root <- local({
  d <- getwd()
  while (!file.exists(file.path(d, "global.R")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "global.R")))
    stop("[helper-repl.R] Could not find the CEDAR repo root from ", getwd())
  d
})

cedar_base_dir <<- .cedar_root
cedar_data_dir <<- file.path(.cedar_root, "data")

source(file.path(.cedar_root, "R", "trunk", "load-funcs.R"))
load_funcs(cedar_base_dir = .cedar_root, modules = FALSE)

# Load a cedar table by name, e.g. cedar_read("cedar_students").
cedar_read <- function(name) {
  p <- file.path(cedar_data_dir, paste0(name, ".qs"))
  if (!file.exists(p)) stop("[helper-repl.R] No such data file: ", p)
  qs2::qs_read(p)
}

# The tables nearly every script wants. Loaded lazily via delayedAssign so
# sourcing this file stays fast when a script only needs one of them.
for (.nm in c("cedar_students", "cedar_programs", "cedar_degrees",
              "cedar_sections", "cedar_grades", "cedar_student_term_credits",
              "cedar_applicants", "cedar_lookups")) {
  local({
    n <- .nm
    if (file.exists(file.path(cedar_data_dir, paste0(n, ".qs")))) {
      delayedAssign(n, cedar_read(n), assign.env = .GlobalEnv)
    }
  })
}
rm(.nm)

message("[helper-repl.R] Ready. Tables load on first use; cedar_read(\"<name>\") for others.")
