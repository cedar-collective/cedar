context("Course Dynamics UI")

test_that("balance values preserve meaningful continuous precision", {
  ui_helpers <- new.env(parent = globalenv())
  sys.source("../../R/modules/ui-helpers.R", envir = ui_helpers)
  values <- ui_helpers$cedar_format_balance_value(
    c(3.234, 3, 57.04, NA_real_),
    c("continuous", "continuous", "binary", "continuous")
  )

  expect_equal(values, c("3.23", "3.00", "57.0", "—"))
})

test_that("Analyze Course is disabled until a course is selected", {
  src <- readLines("../../ui.R", warn = FALSE)

  button_line <- grep('"cr_generate_button"', src, fixed = TRUE)[1]
  button_copy <- paste(src[button_line:min(length(src), button_line + 12L)],
                       collapse = "\n")
  expect_match(button_copy, 'disabled = "disabled"', fixed = TRUE)
  expect_match(button_copy, '`aria-disabled` = "true"', fixed = TRUE)

  guard_start <- grep("cedarCourseAnalyzeGuard", src, fixed = TRUE)[1]
  expect_false(is.na(guard_start))
  guard_copy <- paste(src[max(1L, guard_start - 28L):
                            min(length(src), guard_start + 14L)],
                      collapse = "\n")
  expect_match(guard_copy, "inputId = 'cr_course'", fixed = TRUE)
  expect_match(guard_copy, "buttonId = 'cr_generate_button'", fixed = TRUE)
  expect_match(guard_copy, "button.disabled = !enabled", fixed = TRUE)
  expect_match(guard_copy, "event.name === inputId", fixed = TRUE)
  expect_match(guard_copy, "input.selectize.getValue()", fixed = TRUE)
})

test_that("Enrollment explains its shared crosslist-family scope", {
  src <- paste(readLines("../../ui.R", warn = FALSE), collapse = "\n")

  expect_match(
    src,
    "using the same crosslist-family totals as Overview",
    fixed = TRUE
  )
  expect_match(
    src,
    "registrations under every partner code are combined",
    fixed = TRUE
  )
})
