context("Enrollment controls and deep links")

test_that("Enrollment accepts any narrowing filter except level alone", {
  expect_false(enrollment_scope_is_ready())
  expect_false(enrollment_scope_is_ready(character(0), c("", NA_character_)))
  expect_false(enrollment_scope_is_ready(level = "undergrad"))
  expect_true(enrollment_scope_is_ready(college = "AS"))
  expect_true(enrollment_scope_is_ready(dept_codes = "HIST"))
  expect_true(enrollment_scope_is_ready(c("", "AS"), NULL))
  expect_true(enrollment_scope_is_ready(campus = "ABQ"))
  expect_true(enrollment_scope_is_ready(term = "202680"))
  expect_true(enrollment_scope_is_ready(part_term = "1"))
  expect_true(enrollment_scope_is_ready(subject = "MATH"))
  expect_true(enrollment_scope_is_ready(course = "MATH 375"))
  expect_true(enrollment_scope_is_ready(instructor = "Ada Lovelace"))
  expect_true(enrollment_scope_is_ready(delivery_method = "In Person"))
  expect_true(enrollment_scope_is_ready(gen_ed = "Mathematics"))
})

test_that("Undergraduate expands to the canonical section levels", {
  expect_null(resolve_enrollment_levels(NULL))
  expect_setequal(resolve_enrollment_levels("undergrad"), c("lower", "upper"))
  expect_setequal(
    resolve_enrollment_levels(c("undergrad", "grad", "lower")),
    c("lower", "upper", "grad")
  )
  expect_equal(resolve_enrollment_levels("grad"), "grad")
})

test_that("Enrollment UI defaults to Undergraduate and guards its run button", {
  src <- paste(readLines("../../ui.R", warn = FALSE), collapse = "\n")

  expect_match(src, '"Undergraduate" = "undergrad"', fixed = TRUE)
  expect_match(src, 'selected = "undergrad"', fixed = TRUE)

  button_at <- regexpr('actionButton("enrl_button"', src, fixed = TRUE)[[1]]
  expect_gt(button_at, 0)
  button_copy <- substr(src, button_at, button_at + 450L)
  expect_match(button_copy, 'disabled = "disabled"', fixed = TRUE)
  expect_match(button_copy, '`aria-disabled` = "true"', fixed = TRUE)

  expect_match(src, "cedarEnrollmentScopeGuard", fixed = TRUE)
  expect_match(src, "var narrowingInputs = [", fixed = TRUE)
  expect_match(src, "'enrl_dept', 'enrl_subj', 'enrl_course', 'enrl_inst'", fixed = TRUE)
  expect_false(grepl("'enrl_level'", substr(
    src,
    regexpr("var narrowingInputs = [", src, fixed = TRUE)[[1]],
    regexpr("function hasSelection", src, fixed = TRUE)[[1]]
  ), fixed = TRUE))
  expect_match(src, "button.disabled = !enabled", fixed = TRUE)
})

test_that("Enrollment deep links round-trip the selected course", {
  spec <- CEDAR_SHARE_SPECS[["Enrollment"]]
  expect_true("course" %in% spec$fields)
  expect_equal(spec$types$course, "select_server")

  query_string <- cedar_share_query(
    spec$slug,
    list(college = "AS", dept = "CHEM", level = "undergrad",
         course = "CHEM 1215L")
  )
  expect_match(query_string, "course=CHEM%201215L", fixed = TRUE)

  state <- cedar_parse_link_state(paste0("?", query_string))
  expect_equal(cedar_link_value(state, "Enrollment", "course"), "CHEM 1215L")
  course_item <- cedar_restore_item(spec, state$query, "course")
  expect_equal(course_item$id, "enrl_course")
  expect_equal(course_item$type, "select_server")
  expect_equal(course_item$value, "CHEM 1215L")
})

test_that("Enrollment server gates every run and copies the course value", {
  src <- paste(readLines("../../server.R", warn = FALSE), collapse = "\n")

  expect_match(src, "enrl_run_request <- cedar_run_trigger", fixed = TRUE)
  expect_match(src, "enrl_run <- reactive({", fixed = TRUE)
  expect_match(src, "scope_ready <- enrollment_scope_is_ready(", fixed = TRUE)
  expect_match(src, "subject = isolate(input$enrl_subj)", fixed = TRUE)
  expect_match(src, "course = isolate(input$enrl_course)", fixed = TRUE)
  expect_match(src, "level = isolate(input$enrl_level)", fixed = TRUE)
  expect_match(src, 'spec_title = "Enrollment"', fixed = TRUE)
  expect_match(src, "course  = input$enrl_course", fixed = TRUE)
  expect_match(
    src,
    "aggregate_courses(\n        out$desr_raw",
    fixed = TRUE
  )
})
