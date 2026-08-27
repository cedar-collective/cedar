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
  module_path <- file.path(getwd(), "../../R/modules")

  cone_files <- c(
    "course-neighbors.R", "course-outcomes.R",
    "major-changes.R", "stopout.R", "pathway.R", "population-trend.R",
    "course-demographics.R", "seatfinder.R", "sfr.R", "waitlist.R",
    "enrollment-projections.R"
  )
  branch_files <- c(
    "population.R", "credit-hours.R", "degrees.R", "enrl.R",
    "course-attempts.R", "course-flows.R", "demographics.R", "headcount.R",
    "enrollment-projections.R"
  )
  feature_files <- c(
    "course-report.R", "dept-dashboard.R", "dept-trends.R",
    "gen-ed.R", "regstats.R", "enrollment-projections.R"
  )
  module_files <- c("enrollment-projections.R")

  for (f in cone_files)   expect_true(file.exists(file.path(cone_path,   f)), info = paste("Missing cone:",   f))
  for (f in branch_files) expect_true(file.exists(file.path(branch_path, f)), info = paste("Missing branch:", f))
  for (f in feature_files) expect_true(file.exists(file.path(feature_path, f)), info = paste("Missing feature:", f))
  for (f in module_files) expect_true(file.exists(file.path(module_path, f)), info = paste("Missing module:", f))
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
  expect_no_error(load_funcs(cedar_base_dir, modules = TRUE))
})

test_that("load_funcs() makes expected functions available", {
  # Run the loader in this test instead of depending on the preceding smoke
  # test. CI intentionally has no private config/config.R, so that smoke test is
  # skipped there; calculation functions loaded by helper-load-functions.R must
  # not make this module assertion pass or fail according to test order.
  cedar_base_dir <- normalizePath(file.path(getwd(), "../.."))
  source(file.path(cedar_base_dir, "R/trunk/load-funcs.R"))
  expect_no_error(load_funcs(cedar_base_dir, modules = TRUE))

  # From branches
  expect_true(exists("filter_DESRs"), info = "filter_DESRs should be defined (from filter.R)")
  expect_true(exists("convert_param_to_list"), info = "convert_param_to_list should be defined (from filter.R)")

  # From cones
  expect_true(exists("get_course_demographics"), info = "get_course_demographics should be defined (from course-demographics.R)")
  expect_true(exists("get_headcount"), info = "get_headcount should be defined (from headcount.R)")
  expect_true(exists("get_course_outcome_rates"), info = "get_course_outcome_rates should be defined (from course-attempts.R)")
  expect_true(exists("get_grade_distribution"), info = "get_grade_distribution should be defined (from course-attempts.R)")

  # From modules
  expect_true(exists("enrollmentProjectionsUI"), info = "Enrollment projection UI should be loaded")
  expect_true(exists("enrollmentProjectionsServer"), info = "Enrollment projection server should be loaded")

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
  expect_equal(spec$fields, c("campus", "course"))
  expect_equal(spec$types$course, "select_server")
})

test_that("every runnable deep-link spec declares its early loading overlay", {
  runnable <- Filter(function(spec) !is.null(spec$run), CEDAR_SHARE_SPECS)
  expect_true(all(vapply(runnable, function(spec) {
    !is.null(spec$overlay) && nzchar(spec$overlay)
  }, logical(1))))
})

test_that("autorun readiness compares restored values without order sensitivity", {
  expect_true(cedar_restore_values_match("CHEM 1215L", "CHEM 1215L"))
  expect_true(cedar_restore_values_match(c("EA", "ABQ"), c("ABQ", "EA")))
  expect_false(cedar_restore_values_match(NULL, "CHEM 1215L"))
  expect_false(cedar_restore_values_match("CHEM 1215", "CHEM 1215L"))
})

test_that("link state parses the original query and resolves legacy slugs", {
  state <- cedar_parse_link_state(
    "?tab=department-profile&autorun=true&campus=ABQ,EA&dept=CHEM"
  )
  expect_equal(state$tab_name, "Dept Trends")
  expect_equal(state$query$campus, "ABQ,EA")
  expect_equal(state$query$dept, "CHEM")
})

test_that("link controller accepts bootstrap state present before its first flush", {
  domain <- shiny::MockShinySession$new()
  inputs <- shiny::reactiveValues(
    cedar_link_bootstrap = list(search = "?tab=home", nonce = 1)
  )

  shiny::withReactiveDomain(domain, cedar_link_server(inputs, domain))
  domain$flushReact()

  expect_equal(shiny::isolate(domain$userData$cedar_link_state())$tab_name, "Home")
})

test_that("link restore ignores tabs without a registered restore contract", {
  expect_null(cedar_restore_from_query(NULL, NULL, list(), NULL))
  expect_null(cedar_restore_from_query(NULL, NULL, list(), "Home"))
  expect_null(cedar_restore_from_query(NULL, NULL, list(), "unknown-tab"))
})

test_that("restore schema ignores undeclared URL parameters", {
  spec <- CEDAR_SHARE_SPECS[["Course Dynamics"]]
  query <- list(campus = "ABQ,EA", course = "CHEM 1215L", made_up = "value")
  items <- Filter(Negate(is.null), lapply(spec$fields, function(key) {
    cedar_restore_item(spec, query, key)
  }))

  expect_equal(vapply(items, `[[`, character(1), "key"), c("campus", "course"))
  expect_equal(items[[1]]$id, "cr_campus")
  expect_equal(items[[2]]$id, "cr_course")
})

test_that("generic link restore publishes one server-side run event", {
  domain <- shiny::MockShinySession$new()
  inputs <- shiny::reactiveValues()
  messages <- list()
  run_event <- shiny::reactiveVal(NULL)
  session <- list(sendCustomMessage = function(type, message) {
    messages[[length(messages) + 1L]] <<- list(type = type, message = message)
  })

  shiny::withReactiveDomain(domain, {
    cedar_schedule_link_restore(
      session,
      inputs,
      list(list(
        id = "cr_course", key = "course", type = "select_server",
        value = "CHEM 1215L"
      )),
      autorun = TRUE,
      tab_name = "Course Dynamics",
      run_event = run_event
    )
  })
  domain$flushReact()
  expect_length(messages, 0)

  inputs$cr_course <- "CHEM 1215L"
  domain$flushReact()
  expect_equal(shiny::isolate(run_event())$tab_name, "Course Dynamics")
  expect_length(messages, 0)

  inputs$cr_course <- "CHEM 1215"
  domain$flushReact()
  expect_length(messages, 0)
})

test_that("manual and linked runs share one reusable trigger", {
  domain <- shiny::MockShinySession$new()
  inputs <- shiny::reactiveValues(cr_generate_button = 0)
  domain$userData$cedar_link_run <- shiny::reactiveVal(NULL)
  observed <- integer(0)

  shiny::withReactiveDomain(domain, {
    trigger <- cedar_run_trigger(
      inputs, domain, "cr_generate_button", "Course Dynamics"
    )
    shiny::observeEvent(trigger(), {
      observed <<- c(observed, trigger())
    })
  })
  domain$flushReact()
  expect_length(observed, 0)

  inputs$cr_generate_button <- 1
  domain$flushReact()
  expect_equal(observed, 1L)

  domain$userData$cedar_link_run(list(tab_name = "Course Dynamics", nonce = 1))
  domain$flushReact()
  expect_equal(observed, c(1L, 2L))

  domain$userData$cedar_link_run(list(tab_name = "Enrollment", nonce = 2))
  domain$flushReact()
  expect_equal(observed, c(1L, 2L))
})

test_that("run triggers fail when observer wiring drifts from the registry", {
  domain <- shiny::MockShinySession$new()
  domain$userData$cedar_link_run <- shiny::reactiveVal(NULL)
  inputs <- shiny::reactiveValues()

  expect_error(
    shiny::withReactiveDomain(domain, {
      cedar_run_trigger(inputs, domain, "cr_wrong_button", "Course Dynamics")
    }),
    "expected cr_generate_button"
  )
})

test_that("linked server select reads the shared parsed state", {
  state <- cedar_parse_link_state(
    "?tab=course-dynamics&autorun=true&course=CHEM%201215L"
  )

  expect_equal(
    cedar_link_value(state, "Course Dynamics", "course"),
    "CHEM 1215L"
  )

  other_tab <- cedar_parse_link_state(
    "?tab=enrollment&autorun=true&course=CHEM%201215L"
  )
  expect_null(cedar_link_value(other_tab, "Course Dynamics", "course"))
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
