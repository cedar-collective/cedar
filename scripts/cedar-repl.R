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

# The dimension tables, read from institution/<id>/ as the app reads them.
cedar_dims <- build_cedar_dims()

# Load a local CEDAR table by name, e.g. cedar_read("cedar_students"). A fact
# table gets its default unit columns attached here, as global.R attaches
# them (ADR-001 step 3), so an ad-hoc number is on the app's units; sections
# and class lists also get course_id (step 4), from the dimension below.
cedar_read <- function(name) {
  path <- file.path(cedar_data_dir, paste0(name, ".qs"))
  if (!file.exists(path)) stop("[cedar-repl.R] No such data file: ", path)
  tbl <- qs2::qs_read(path)
  # As global.R loads it: the student descriptions are read off
  # cedar_student_terms, never the class list (ADR-001 step 5).
  if (name == "cedar_students") tbl <- thin_class_list(tbl)
  if (name %in% names(CEDAR_ATTACHED_UNIT_COLUMNS)) {
    tbl <- suppressMessages(attach_default_units(stats::setNames(list(tbl), name), cedar_dims))[[name]]
  }
  if (name %in% names(CEDAR_ATTACHED_COURSE_COLUMNS)) {
    tbl <- suppressMessages(attach_course_ids(stats::setNames(list(tbl), name), cedar_courses))[[name]]
  }
  tbl
}

# The course dimension, built from the saved sections and class lists on first
# use (both files are read for it, whichever table was asked for), as
# global.R builds it. cedar_courses$courses and cedar_courses$codes are the
# two tables the app holds as cedar_courses and cedar_course_codes.
delayedAssign("cedar_courses", {
  raw <- function(name) qs2::qs_read(file.path(cedar_data_dir, paste0(name, ".qs")))
  build_cedar_courses(raw("cedar_sections"), raw("cedar_students"), cedar_dims)
})

# Tables load lazily so sourcing remains fast when only one is needed.
for (.nm in c("cedar_students", "cedar_programs", "cedar_degrees",
              "cedar_sections", "cedar_student_terms",
              "cedar_applicants")) {
  local({
    name <- .nm
    if (file.exists(file.path(cedar_data_dir, paste0(name, ".qs")))) {
      delayedAssign(name, cedar_read(name), assign.env = .GlobalEnv)
    }
  })
}
rm(.nm)

# cedar_attempts, every graded attempt classified once, as global.R builds it
# (R/branches/attempts.R): over the keyed class list, to the graded edge.
delayedAssign("cedar_attempts", build_attempts(
  cedar_students, cedar_report_edges(cedar_students, degrees = cedar_degrees)$edges))

message("[cedar-repl.R] Ready. Tables load on first use; cedar_read(\"<name>\") for others.")
