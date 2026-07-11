# Tests for course-outcomes.R functions
# Tests R/cones/course-outcomes.R: next_term_persistence, get_course_outcomes
#
# Uses test_students and test_faculty (from fixtures/designed_test_data.R).
#
# Reference values (from designed_test_data.R fixtures):
#   HIST 1110 (all terms): 23 pass, 4 fail, 9 late drop
#   next_term_persistence(HIST 1110, min_n=1):
#     pass: 23 students, 0 returned (no later-term enrollment in fixture)
#     fail:  4 students, 0 returned
#     late drop: 9 students, 0 returned
#   get_course_outcomes(HIST 1110, min_n=1):
#     persistence: 3 rows (pass/fail/late drop)
#     dfw_trend: 4 rows (grades assigned across all 4 terms in fixture)
#     instructor_dfw: 1 row
#     cedar_faculty=NULL: dfw_trend still computed from get_grades (no gating on faculty)

context("Course Outcomes")


# =============================================================================
# next_term_persistence() tests
# =============================================================================

test_that("next_term_persistence returns correct structure", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR", "DR", "DG", "DW")) %>%
    dedup_enrollment(level = "course")

  result <- next_term_persistence(filtered, test_students, opt = list(min_n = 1))

  expect_s3_class(result, "data.frame")
  expect_true("subject_course" %in% names(result))
  expect_true("outcome"        %in% names(result))
  expect_true("n_students"     %in% names(result))
  expect_true("n_returned"     %in% names(result))
  expect_true("pct_returned"   %in% names(result))
})

test_that("next_term_persistence classifies pass, fail, and late drop outcomes for HIST 1110", {
  # Fixture has W grades, which are kept distinct from non-W failing grades.
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR", "DR", "DG", "DW")) %>%
    dedup_enrollment(level = "course")

  result <- next_term_persistence(filtered, test_students, opt = list(min_n = 1))

  expect_setequal(result$outcome, c("pass", "fail", "late drop"))
})

test_that("next_term_persistence student counts match fixture for HIST 1110", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR", "DR", "DG", "DW")) %>%
    dedup_enrollment(level = "course")

  result <- next_term_persistence(filtered, test_students, opt = list(min_n = 1))

  pass_row <- result[result$outcome == "pass", ]
  fail_row  <- result[result$outcome == "fail",  ]
  late_row  <- result[result$outcome == "late drop",  ]

  expect_equal(pass_row$n_students, 23)
  expect_equal(fail_row$n_students,   4)
  expect_equal(late_row$n_students,   9)
})

test_that("next_term_persistence pass group has zero returns in fixture", {
  # Fixture has no later-term enrollment for HIST 1110 pass students
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR", "DR")) %>%
    dedup_enrollment(level = "course")

  result <- next_term_persistence(filtered, test_students, opt = list(min_n = 1))

  pass_row <- result[result$outcome == "pass", ]
  expect_equal(pass_row$n_returned, 0L)
})

test_that("next_term_persistence respects min_n filter", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR", "DR")) %>%
    dedup_enrollment(level = "course")

  # min_n=10 should exclude the drop group (6 students) and reduce rows
  result_high <- next_term_persistence(filtered, test_students, opt = list(min_n = 10))
  result_low  <- next_term_persistence(filtered, test_students, opt = list(min_n = 1))

  expect_lte(nrow(result_high), nrow(result_low))
  expect_true(all(result_high$n_students >= 10))
})

test_that("next_term_persistence returns empty tibble when all final_grades are NA", {
  # Replace all grades with NA and use non-DR status: no outcome can be classified
  no_grades <- test_students %>%
    filter(subject_course == "HIST 1110") %>%
    mutate(final_grade = NA_character_,
           registration_status_code = "RE") %>%
    dedup_enrollment(level = "course")

  result <- next_term_persistence(no_grades, test_students, opt = list(min_n = 1))
  expect_equal(nrow(result), 0)
})


# =============================================================================
# get_course_outcomes() tests
# =============================================================================

test_that("get_course_outcomes returns correct list structure", {
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "HIST 1110", min_n = 1))

  expect_type(result, "list")
  expect_true("persistence"    %in% names(result))
  expect_true("dfw_trend"      %in% names(result))
  expect_true("instructor_dfw" %in% names(result))
  expect_true("courses"        %in% names(result))
})

test_that("get_course_outcomes persistence has pass/fail/late drop rows for HIST 1110", {
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "HIST 1110", min_n = 1))

  expect_equal(nrow(result$persistence), 3)
  expect_setequal(result$persistence$outcome, c("pass", "fail", "late drop"))
})

test_that("get_course_outcomes dfw_trend has 4 rows for HIST 1110 (grades in all 4 terms)", {
  # Designed fixture assigns grades to HIST 1110 across all 4 terms
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "HIST 1110"))

  expect_equal(nrow(result$dfw_trend), 4)
  expect_true("dfw_pct" %in% names(result$dfw_trend))
})

test_that("get_course_outcomes instructor_dfw has required columns", {
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "HIST 1110"))

  expect_gt(nrow(result$instructor_dfw), 0)
  expect_true("dfw_pct"        %in% names(result$instructor_dfw))
  expect_true("course_avg_dfw" %in% names(result$instructor_dfw))
  expect_true("dfw_diff"       %in% names(result$instructor_dfw))
})

test_that("get_course_outcomes dfw_diff equals instructor_dfw_pct minus course_avg", {
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "HIST 1110"))

  if (nrow(result$instructor_dfw) > 0) {
    expected_diff <- round(result$instructor_dfw$dfw_pct - result$instructor_dfw$course_avg_dfw, 3)
    expect_equal(result$instructor_dfw$dfw_diff, expected_diff)
  }
})

test_that("get_course_outcomes requires opt$course", {
  expect_error(get_course_outcomes(test_students),
               regexp = "opt\\$course is required")
})

test_that("get_course_outcomes returns empty tibbles for nonexistent course", {
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "NONEXISTENT 9999"))

  expect_equal(nrow(result$persistence),    0)
  expect_equal(nrow(result$dfw_trend),      0)
  expect_equal(nrow(result$instructor_dfw), 0)
})

test_that("get_course_outcomes persistence only contains the requested course", {
  result <- get_course_outcomes(test_students, cedar_faculty = NULL,
                                opt = list(course = "HIST 1110", min_n = 1))

  expect_true(all(result$persistence$subject_course == "HIST 1110"))
})

test_that("get_course_outcomes dfw_trend and instructor_dfw are non-empty even when cedar_faculty = NULL", {
  # get_grades does not require cedar_faculty; dfw_trend/instructor_dfw come from grade data alone
  result <- get_course_outcomes(test_students, cedar_faculty = NULL, opt = list(course = "HIST 1110"))
  expect_equal(nrow(result$dfw_trend),      4)
  expect_equal(nrow(result$instructor_dfw), 1)
})
