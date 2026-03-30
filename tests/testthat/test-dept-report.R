# Tests for dept-report.R
# Tests R/reports/dept-report.R
#
# create_dept_report_data() orchestrates set_payload() plus headcount, degrees,
# credit-hours, grades, enrollment, and SFR cones. set_payload() reads global
# maps loaded by load_funcs() (major_to_dept, dept_code_to_name,
# cedar_report_start_term), so the full pipeline can't be
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


# =============================================================================
# count_degrees() — unit tests (no globals required)
# =============================================================================

test_that("count_degrees returns a data frame with required columns", {
  result <- count_degrees(test_degrees)
  expect_true(is.data.frame(result))
  expect_true(all(c("term", "major_code", "degree", "majors") %in% names(result)),
              info = paste("Missing columns:", paste(setdiff(c("term","major_code","degree","majors"), names(result)), collapse=", ")))
})

test_that("count_degrees does not include a bare 'major' column", {
  result <- count_degrees(test_degrees)
  expect_false("major" %in% names(result),
               info = "count_degrees should group by major_code, not major name")
})

test_that("count_degrees returns correct degree counts for HIST", {
  result <- count_degrees(test_degrees)
  hist_rows <- result[result$major_code == "HIST" & result$degree == "BA", ]
  # Fixture: DEG001+DEG002 in 202060, DEG007 in 202080, DEG010 in 202110, DEG011 in 202080
  # → 202060: 2, 202080: 2 (DEG007 + DEG011), 202110: 1
  expect_equal(sum(hist_rows$majors), 5L,
               info = "Expected 5 total HIST BA degrees across all terms")
})

test_that("count_degrees handles data with no rows gracefully", {
  empty <- test_degrees[FALSE, ]
  result <- count_degrees(empty)
  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 0L)
})


# =============================================================================
# get_degrees_for_dept_report() — integration tests
# =============================================================================

test_that("get_degrees_for_dept_report returns list with plots and tables keys", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  expect_true(is.list(result))
  expect_true(all(c("plots", "tables") %in% names(result)))
})

test_that("get_degrees_for_dept_report tables contain major_code not major", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  deg_filtered <- result$tables$degree_summary_filtered
  expect_true("major_code" %in% names(deg_filtered),
              info = "degree_summary_filtered must have major_code column")
  expect_false("major" %in% names(deg_filtered),
               info = "degree_summary_filtered should not have a bare 'major' column")
})

test_that("get_degrees_for_dept_report filters to the requested prog_codes", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  deg_filtered <- result$tables$degree_summary_filtered
  expect_true(all(deg_filtered$major_code == "HIST"),
              info = "All rows should have major_code == 'HIST'")
})

test_that("get_degrees_for_dept_report produces NULL plots when prog_codes has no matches", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "Nonexistent",
    prog_codes = "NOSUCH",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  expect_null(result$plots$degree_summary_faceted_by_major_plot)
  expect_null(result$plots$degree_summary_filtered_program_stacked_plot)
  expect_equal(nrow(result$tables$degree_summary_filtered), 0L)
})
