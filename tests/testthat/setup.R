# Test setup - runs before all tests
#
# DESIGNED FIXTURES (test_sections, test_students, etc.)
#   Hand-crafted, transparent, inspectable. Source of truth is
#   fixtures/designed_test_data.R — edit that file to change test data.
#   XL/crosslist sections live in test_sections alongside regular sections,
#   exactly as they do in production. Tests filter from test_sections directly.

# Load necessary libraries
suppressPackageStartupMessages({
  library(dplyr)
})

# -----------------------------------------------------------------------------
# DESIGNED FIXTURES - hand-crafted, transparent, and inspectable
# -----------------------------------------------------------------------------
source("fixtures/designed_test_data.R")

test_sections    <<- cedar_sections
test_sections_sf <<- cedar_sections_sf   # seatfinder-specific: 2024/2025 terms (test-seatfinder.R)
test_students    <<- cedar_students
test_programs    <<- cedar_programs
test_degrees     <<- cedar_degrees
test_faculty     <<- cedar_faculty

data_objects <<- list(
  cedar_programs = test_programs,
  cedar_degrees  = test_degrees,
  cedar_students = test_students,
  cedar_faculty  = test_faculty,
  cedar_sections = test_sections
)

Sys.setenv(shiny = "FALSE")

# Config globals — minimal values sufficient for test runs
cedar_regstats_thresholds <<- list(
  min_impacted      = 20,
  pct_sd            = 1,
  chronic_fill_rate = 0.90,
  min_wait          = 20,
  section_proximity = 0.3
)
cedar_data_dir <<- tempdir()

# Report config globals — required by set_payload() (dept-report.R) and course-report.R
cedar_report_start_term <<- 202010L
cedar_report_end_term   <<- 202110L
cedar_report_palette    <<- "Spectral"

message(sprintf("  test_sections: %d rows (%d XL) | test_students: %d rows | test_programs: %d rows",
                nrow(test_sections),
                sum(!is.na(test_sections$crosslist_group)),
                nrow(test_students), nrow(test_programs)))
message(sprintf("  test_faculty:  %d rows | test_degrees:  %d rows",
                nrow(test_faculty), nrow(test_degrees)))

# Helper function to create standard opt list
create_test_opt <- function(overrides = list()) {
  default_opt <- list(
    course_campus  = NULL,
    course_college = NULL,
    dept           = NULL,
    term           = NULL,
    pt             = NULL,
    im             = NULL,
    level          = NULL,
    status         = "A",
    uel            = TRUE,
    group_cols     = NULL,
    bypass_cache   = TRUE   # always recompute in tests; never read production cache
  )

  modifyList(default_opt, overrides)
}
