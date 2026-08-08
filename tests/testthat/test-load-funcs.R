# Tests for load-funcs()
# Tests R/trunk/load-funcs.R
#
# This file tests that the central function loader works correctly,
# including file existence checks and proper function loading.

context("Function Loading (load-funcs)")

# =============================================================================
# File Existence Tests
# =============================================================================

test_that("load-funcs.R exists in expected location", {
  load_funcs_path <- file.path(getwd(), "../../R/trunk/load-funcs.R")
  expect_true(file.exists(load_funcs_path))
})

test_that("all list files exist", {
  base_path <- file.path(getwd(), "../../R/lists")
  expected_files <- c(
    "excluded_courses.R",
    "gen_ed_courses.R",
    "grades.R",
    "subj_dept_map.R",
    "catalog_lookups.R",
    "mappings.R"
  )

  for (f in expected_files) {
    file_path <- file.path(base_path, f)
    expect_true(file.exists(file_path), info = paste("Missing:", f))
  }
})

test_that("all trunk files exist", {
  base_path <- file.path(getwd(), "../../R/trunk")
  expected_files <- c(
    "cache.R",
    "changelog.R",
    "data.R",
    "datatable_helpers.R",
    "filter.R",
    "load-funcs.R",
    "logging.R",
    "reporting.R",
    "utils.R"
  )

  for (f in expected_files) {
    file_path <- file.path(base_path, f)
    expect_true(file.exists(file_path), info = paste("Missing:", f))
  }
})

test_that("all cone files exist", {
  cone_path   <- file.path(getwd(), "../../R/cones")
  branch_path <- file.path(getwd(), "../../R/branches")
  feature_path <- file.path(getwd(), "../../R/features")

  cone_files <- c(
    "course-neighbors.R", "course-outcomes.R",
    "major-changes.R", "stopout.R", "pathway.R", "population-trend.R",
    "course-demographics.R", "seatfinder.R", "sfr.R", "waitlist.R"
  )
  branch_files <- c(
    "population.R", "credit-hours.R", "degrees.R", "enrl.R",
    "course-attempts.R", "course-flows.R", "demographics.R", "headcount.R"
  )
  feature_files <- c(
    "course-report.R", "dept-dashboard.R", "dept-trends.R",
    "gen-ed.R", "regstats.R"
  )

  for (f in cone_files)   expect_true(file.exists(file.path(cone_path,   f)), info = paste("Missing cone:",   f))
  for (f in branch_files) expect_true(file.exists(file.path(branch_path, f)), info = paste("Missing branch:", f))
  for (f in feature_files) expect_true(file.exists(file.path(feature_path, f)), info = paste("Missing feature:", f))
})

# =============================================================================
# load_funcs() Smoke Test
# =============================================================================

test_that("load_funcs() loads calculation stack without errors when config is available", {
  # Get the cedar base directory (2 levels up from tests/testthat)
  cedar_base_dir <- normalizePath(file.path(getwd(), "../.."))

  # Check if config exists - skip if not available
  config_path <- file.path(cedar_base_dir, "config/config.R")
  if (!file.exists(config_path)) {
    skip("config/config.R not found - required for full load_funcs test")
  }

  # config.R is the developer's real local config; source()ing it with the default
  # local = FALSE assigns its cedar_* globals into .GlobalEnv, overwriting the test
  # values setup.R installed (e.g. cedar_regstats_thresholds, cedar_data_dir,
  # cedar_report_* terms). Snapshot every global it could touch and restore them when
  # this test exits so it does not leak production config into later, order-dependent
  # tests (this previously made regstats flag 3 bumps instead of 1 in full-suite runs).
  cfg_globals <- c("cedar_regstats_thresholds", "cedar_data_dir", "cedar_output_dir",
                   "cedar_base_dir", "cedar_current_term", "cedar_report_start_term",
                   "cedar_report_end_term", "cedar_report_palette")
  present <- cfg_globals[vapply(cfg_globals, exists, logical(1),
                                envir = .GlobalEnv, inherits = FALSE)]
  saved <- mget(present, envir = .GlobalEnv)
  withr::defer(list2env(saved, envir = .GlobalEnv))

  # Source config first (load_funcs depends on config variables like cedar_data_dir)
  source(config_path)

  # Source and run load_funcs
  source(file.path(cedar_base_dir, "R/trunk/load-funcs.R"))

  # This should complete without error
  expect_no_error(load_funcs(cedar_base_dir, modules = FALSE))
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
  expect_true(exists("get_course_demographics"), info = "get_course_demographics should be defined (from course-demographics.R)")
  expect_true(exists("get_headcount"), info = "get_headcount should be defined (from headcount.R)")
  expect_true(exists("get_course_outcome_rates"), info = "get_course_outcome_rates should be defined (from course-attempts.R)")
  expect_true(exists("get_grade_distribution"), info = "get_grade_distribution should be defined (from course-attempts.R)")

  # From lists (these are typically named vectors, not functions)
  # Catalog tibbles
  expect_true(exists("subj_dept_map"),    info = "subj_dept_map should be defined (from subj_dept_map.R)")
  expect_true(exists("program_map"),      info = "program_map should be defined (from data/program_map.qs)")
  # Lookup vectors derived from catalogs (catalog_lookups.R)
  expect_true(exists("subj_to_dept"),     info = "subj_to_dept should be defined (from catalog_lookups.R)")
  expect_true(exists("dept_code_to_name"),    info = "dept_code_to_name should be defined (from catalog_lookups.R)")
  expect_true(exists("college_name_to_code"), info = "college_name_to_code should be defined (from catalog_lookups.R)")
  expect_true(exists("major_college_to_dept"),        info = "major_college_to_dept should be defined (from catalog_lookups.R)")
  expect_true(exists("major_to_dept"),    info = "major_to_dept should be defined (from catalog_lookups.R)")
  # Text/name maps retained in mappings.R
  expect_true(exists("major_name_to_major_code"), info = "major_name_to_major_code should be defined (from mappings.R)")
  expect_true(exists("hr_org_desc_to_dept"),      info = "hr_org_desc_to_dept should be defined (from mappings.R)")
  expect_true(exists("passing_grades"), info = "passing_grades should be defined (from grades.R)")
})

test_that("Course Dynamics share spec targets the standard analyze button", {
  expect_true(exists("CEDAR_SHARE_SPECS"))
  spec <- CEDAR_SHARE_SPECS[["Course Dynamics"]]
  expect_equal(spec$slug, "course-dynamics")
  expect_equal(spec$prefix, "cr")
  expect_equal(spec$run, "generate_button")
  expect_equal(spec$types$course, "select_server")
})

test_that("autorun readiness compares restored values without order sensitivity", {
  expect_true(cedar_restore_values_match("CHEM 1215L", "CHEM 1215L"))
  expect_true(cedar_restore_values_match(c("EA", "ABQ"), c("ABQ", "EA")))
  expect_false(cedar_restore_values_match(NULL, "CHEM 1215L"))
  expect_false(cedar_restore_values_match("CHEM 1215", "CHEM 1215L"))
})

test_that("generic autorun waits for inputs and clicks its registered button once", {
  domain <- shiny::MockShinySession$new()
  inputs <- shiny::reactiveValues()
  messages <- list()
  session <- list(sendCustomMessage = function(type, message) {
    messages[[length(messages) + 1L]] <<- list(type = type, message = message)
  })

  shiny::withReactiveDomain(domain, {
    cedar_schedule_autorun(
      session,
      inputs,
      "cr_generate_button",
      list(list(id = "cr_course", value = "CHEM 1215L"))
    )
  })
  domain$flushReact()
  expect_length(messages, 0)

  inputs$cr_course <- "CHEM 1215L"
  domain$flushReact()
  expect_length(messages, 0)

  inputs$cr_generate_button <- 0
  domain$flushReact()
  expect_equal(messages, list(list(
    type = "click_button",
    message = "cr_generate_button"
  )))

  inputs$cr_generate_button <- 1
  inputs$cr_course <- "CHEM 1215"
  domain$flushReact()
  expect_length(messages, 1)
})

test_that("Course Dynamics deep-link course is available during selectize initialization", {
  session <- list(clientData = list(
    url_search = "?tab=course-dynamics&autorun=true&course=CHEM%201215L"
  ))

  expect_equal(
    cedar_url_restore_value(session, "Course Dynamics", "course"),
    "CHEM 1215L"
  )

  other_tab <- list(clientData = list(
    url_search = "?tab=enrollment&autorun=true&course=CHEM%201215L"
  ))
  expect_null(cedar_url_restore_value(other_tab, "Course Dynamics", "course"))
})


# =============================================================================
# Error Handling Tests
# =============================================================================

test_that("load_funcs() fails gracefully with bad path", {
  source(file.path(getwd(), "../../R/trunk/load-funcs.R"))

  # Should error with a clear message when path is invalid

  expect_error(
    load_funcs("/nonexistent/path"),
    "File not found"
  )
})
