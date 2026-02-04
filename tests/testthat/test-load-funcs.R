# Tests for load-funcs()
# Tests R/branches/load-funcs.R
#
# This file tests that the central function loader works correctly,
# including file existence checks and proper function loading.

context("Function Loading (load-funcs)")

# =============================================================================
# File Existence Tests
# =============================================================================

test_that("load-funcs.R exists in expected location", {
  load_funcs_path <- file.path(getwd(), "../../R/branches/load-funcs.R")
  expect_true(file.exists(load_funcs_path))
})

test_that("all list files exist", {
  base_path <- file.path(getwd(), "../../R/lists")
  expected_files <- c(
    "drop_cols.R",
    "excluded_courses.R",
    "gen_ed_courses.R",
    "grades.R",
    "mappings.R",
    "terms.R"
  )

  for (f in expected_files) {
    file_path <- file.path(base_path, f)
    expect_true(file.exists(file_path), info = paste("Missing:", f))
  }
})

test_that("all branch files exist", {
  base_path <- file.path(getwd(), "../../R/branches")
  expected_files <- c(
    "cache.R",
    "changelog.R",
    "data.R",
    "datatable_helpers.R",
    "filter.R",
    "load-funcs.R",
    "logging.R",
    "command-handler.R",
    "reporting.R",
    "utils.R"
  )

  for (f in expected_files) {
    file_path <- file.path(base_path, f)
    expect_true(file.exists(file_path), info = paste("Missing:", f))
  }
})

test_that("all cone files exist", {
  base_path <- file.path(getwd(), "../../R/cones")
  expected_files <- c(
    "course-report.R",
    "credit-hours.R",
    "degrees.R",
    "dept-report.R",
    "enrl.R",
    "gradebook.R",
    "headcount.R",
    "lookout.R",
    "majors.R",
    "outcomes.R",
    "regstats.R",
    "rollcall.R",
    "seatfinder.R",
    "sfr.R",
    "waitlist.R"
  )

  for (f in expected_files) {
    file_path <- file.path(base_path, f)
    expect_true(file.exists(file_path), info = paste("Missing:", f))
  }
})

test_that("forecast files exist", {
  base_path <- file.path(getwd(), "../../R/cones/forecast")
  expected_files <- c(
    "forecast.R",
    "forecast-stats.R"
  )

  for (f in expected_files) {
    file_path <- file.path(base_path, f)
    expect_true(file.exists(file_path), info = paste("Missing:", f))
  }
})


# =============================================================================
# load_funcs() Smoke Test
# =============================================================================

test_that("load_funcs() loads without errors when config is available", {
  # Get the cedar base directory (2 levels up from tests/testthat)
  cedar_base_dir <- normalizePath(file.path(getwd(), "../.."))

  # Check if config exists - skip if not available
  config_path <- file.path(cedar_base_dir, "config/config.R")
  if (!file.exists(config_path)) {
    skip("config/config.R not found - required for full load_funcs test")
  }

  # Source config first (load_funcs depends on config variables like cedar_data_dir)
  source(config_path)

  # Source and run load_funcs
  source(file.path(cedar_base_dir, "R/branches/load-funcs.R"))

  # This should complete without error
  expect_no_error(load_funcs(cedar_base_dir))
})

test_that("load_funcs() makes expected functions available", {
  # This test depends on the previous test having run successfully
  # Check if a function from load_funcs exists to determine if we can run

  if (!exists("filter_DESRs")) {
    skip("load_funcs() did not run - skipping function availability test")
  }

  # From branches
  expect_true(exists("filter_DESRs"), info = "filter_DESRs should be defined (from filter.R)")
  expect_true(exists("convert_param_to_list"), info = "convert_param_to_list should be defined (from filter.R)")

  # From cones
  expect_true(exists("rollcall"), info = "rollcall should be defined (from rollcall.R)")
  expect_true(exists("get_headcount"), info = "get_headcount should be defined (from headcount.R)")
  expect_true(exists("get_grades"), info = "get_grades should be defined (from gradebook.R)")

  # From lists (these are typically named vectors, not functions)
  expect_true(exists("prgm_to_dept_map"), info = "prgm_to_dept_map should be defined (from mappings.R)")
  expect_true(exists("passing_grades"), info = "passing_grades should be defined (from grades.R)")
})


# =============================================================================
# Error Handling Tests
# =============================================================================

test_that("load_funcs() fails gracefully with bad path", {
  source(file.path(getwd(), "../../R/branches/load-funcs.R"))

  # Should error with a clear message when path is invalid

  expect_error(
    load_funcs("/nonexistent/path"),
    "File not found"
  )
})
