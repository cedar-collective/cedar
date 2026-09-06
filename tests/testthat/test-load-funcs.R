# The calculation stack is loaded by helper-load-functions.R for every suite.
# Test the optional module path and loader error, plus deep-link behavior.
context("Function Loading and Deep Links")

test_that("load_funcs loads optional Shiny modules", {
  expect_no_error(load_funcs(cedar_base_dir, modules = TRUE))
  expect_type(enrollmentProjectionsUI, "closure")
  expect_type(enrollmentProjectionsServer, "closure")
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
