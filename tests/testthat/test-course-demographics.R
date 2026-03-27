# Tests for get_course_demographics function
# Tests R/cones/course-demographics.R
#
# Uses test_students (cedar_students_test.qs).
#
# Reference values (from designed_test_data.R fixtures):
#   HIST 1110 registered (RE/RS/RR): 27 students across 4 terms
#   HIST courses in students: HIST 1110, HIST 327, HIST 490, HIST 601
#   calc_cl_enrls(HIST): 14 distinct course-term-campus rows

context("Course Demographics")


# =============================================================================
# summarize_student_demographics() tests
# =============================================================================

test_that("summarize_student_demographics returns correct structure", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR"))

  opt    <- list(group_cols = c("campus", "college", "term", "term_type",
                                "student_classification", "subject_course"))
  result <- summarize_student_demographics(filtered, opt)

  expect_s3_class(result, "data.frame")
  expect_true("count"         %in% names(result))
  expect_true("mean"          %in% names(result))
  expect_true("registered"    %in% names(result))
  expect_true("term_pct"      %in% names(result))
  expect_true("term_type_pct" %in% names(result))
})

test_that("summarize_student_demographics groups by student_classification", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR"))

  opt    <- list(group_cols = c("campus", "college", "term", "term_type",
                                "student_classification", "subject_course"))
  result <- summarize_student_demographics(filtered, opt)

  expect_true("student_classification" %in% names(result))
  # 27 registered HIST 1110 students across all terms
  expect_equal(sum(result$count), 27)
})

test_that("summarize_student_demographics pct sums to 100 per term", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% c("RE", "RS", "RR"))

  opt    <- list(group_cols = c("campus", "college", "term", "term_type",
                                "student_classification", "subject_course"))
  result <- summarize_student_demographics(filtered, opt)

  pct_sums <- result %>%
    group_by(term) %>%
    summarize(total = sum(term_pct), .groups = "drop")

  expect_true(all(abs(pct_sums$total - 100) < 1))
})


# =============================================================================
# get_course_demographics() tests
# =============================================================================

test_that("get_course_demographics returns correct structure", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  expect_s3_class(result, "data.frame")
  expect_true("count"    %in% names(result))
  expect_true("mean"     %in% names(result))
  expect_true("term_pct" %in% names(result))
})

test_that("get_course_demographics default output includes classification and major columns", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  expect_true("student_classification" %in% names(result))
  expect_true("major_code"             %in% names(result))
})

test_that("get_course_demographics filters to requested course only", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  expect_true(all(result$subject_course == "HIST 1110"))
})

test_that("get_course_demographics total count matches registered students for HIST 1110", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  # 27 registered (RE/RS/RR) HIST 1110 students in the fixture
  expect_equal(sum(result$count), 27)
})

test_that("get_course_demographics filters by term correctly", {
  result <- get_course_demographics(test_students, list(term = 202010))

  expect_true(all(result$term == 202010))
  expect_gt(nrow(result), 0)
})

test_that("get_course_demographics filters by department correctly", {
  result <- get_course_demographics(test_students, list(dept = "HIST"))

  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_setequal(unique(result$term), c(202010, 202060, 202080, 202110))
})

test_that("get_course_demographics excludes early drops from count", {
  # HIST 1120 has both registered and DR (early drop) students
  # Only registered should appear in counts
  hist_1120_reg <- test_students %>%
    filter(subject_course == "HIST 1120",
           registration_status_code %in% c("RE", "RS", "RR")) %>%
    nrow()

  result <- get_course_demographics(test_students, list(course = "HIST 1120"))
  expect_equal(sum(result$count), hist_1120_reg)
})

test_that("get_course_demographics returns empty data frame for nonexistent course", {
  result <- get_course_demographics(test_students, list(course = "NONEXISTENT 9999"))

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_course_demographics respects custom group_cols", {
  opt <- list(
    course     = "HIST 1110",
    group_cols = c("campus", "college", "term", "term_type",
                   "student_classification", "subject_course")
  )
  result <- get_course_demographics(test_students, opt)

  expect_true("student_classification" %in% names(result))
  expect_false("major_code" %in% names(result))
})

test_that("get_course_demographics combined dept + term filter works", {
  result <- get_course_demographics(test_students, list(dept = "HIST", term = 202010))

  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_true(all(result$term == 202010))
})


# =============================================================================
# calc_cl_enrls() tests
# =============================================================================

test_that("calc_cl_enrls returns correct structure", {
  filtered <- test_students %>%
    filter(department == "HIST",
           registration_status_code %in% c("RE", "RS", "RR"))

  result <- calc_cl_enrls(filtered)

  expect_s3_class(result, "data.frame")
  expect_true("registered"      %in% names(result))
  expect_true("registered_mean" %in% names(result))
  expect_true("subject_course"  %in% names(result))
})

test_that("calc_cl_enrls returns a row per course for HIST department", {
  filtered <- test_students %>%
    filter(department == "HIST",
           registration_status_code %in% c("RE", "RS", "RR"))

  result <- calc_cl_enrls(filtered)

  # 14 rows = 4 distinct HIST courses × terms × campus combos
  expect_equal(nrow(result), 14)
  expect_true("HIST 1110" %in% result$subject_course)
  expect_true("HIST 327"  %in% result$subject_course)
})
