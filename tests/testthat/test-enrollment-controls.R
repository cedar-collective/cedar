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
