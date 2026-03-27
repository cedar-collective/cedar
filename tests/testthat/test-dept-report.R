# Tests for dept-report.R
# Tests R/reports/dept-report.R
#
# create_dept_report_data() orchestrates set_payload() plus headcount, degrees,
# credit-hours, grades, enrollment, and SFR cones. set_payload() reads global
# maps loaded by load_funcs() (major_to_dept, major_to_program,
# dept_code_to_name, cedar_report_start_term), so the full pipeline can't be
# unit tested without those globals.
#
# What IS testable without globals:
#   - Upfront input validation (missing dataset keys) — fails before set_payload()
#
# What requires refactoring to test:
#   - set_payload() — reads globals; should accept maps as parameters
#   - create_dept_report_data() full pipeline — depends on set_payload()
#
# All tests use test_* fixtures — no inline tibbles, no known_* data.

context("Department Report")

# Helper: build a complete data_objects list from standard test fixtures.
make_data_objects <- function() {
  list(
    cedar_programs = test_programs,
    cedar_degrees  = test_degrees,
    cedar_students = test_students,
    cedar_faculty  = test_faculty,
    cedar_sections = test_sections
  )
}


# =============================================================================
# Input validation (fails before set_payload() — no globals required)
# =============================================================================

test_that("create_dept_report_data stops on missing dataset key", {
  partial <- make_data_objects()
  partial[["cedar_programs"]] <- NULL

  expect_error(
    create_dept_report_data(partial, list(dept = "HIST")),
    regexp = "Missing required CEDAR datasets"
  )
})

test_that("create_dept_report_data stops when all five required keys are missing", {
  expect_error(
    create_dept_report_data(list(), list(dept = "HIST")),
    regexp = "Missing required CEDAR datasets"
  )
})
