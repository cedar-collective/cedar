context("Course Dynamics UI guards")

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
