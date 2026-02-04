# Tests for rollcall function
# Tests R/cones/rollcall.R
#
# Uses known_students fixture from fixtures/known_test_data.R
# See fixture file for expected values documentation
#
# Expected data from known_students fixture:
#   - 24 total enrollments across 6 sections
#   - Terms: 202510 (18 enrollments), 202560 (4), 202580 (2)
#   - Registration status: RE (22), DR (2 early drops)
#   - Classifications: Freshman (9), Sophomore (9), Junior (4), Senior (2)
#   - Primary majors: History (9), Mathematics (5), Computer Science (4), Anthropology (6)

# Source the rollcall functions
source("../../R/cones/rollcall.R")
source("../../R/cones/enrl.R")
source("../../R/branches/filter.R")

context("Rollcall (Student Demographics)")

# =============================================================================
# summarize_student_demographics() tests
# =============================================================================

test_that("summarize_student_demographics returns correct structure", {
  # Filter students to just registered (RE/RS) for a specific course
  filtered <- known_students %>%
    filter(registration_status_code %in% c("RE", "RS"),
           subject_course == "HIST 1110")

  opt <- list(group_cols = c("campus", "college", "term", "term_type",
                             "student_classification", "subject_course"))

  result <- summarize_student_demographics(filtered, opt)

  expect_s3_class(result, "data.frame")
  expect_true("count" %in% colnames(result))
  expect_true("mean" %in% colnames(result))
  expect_true("registered" %in% colnames(result))
  expect_true("term_pct" %in% colnames(result))
  expect_true("term_type_pct" %in% colnames(result))
})

test_that("summarize_student_demographics groups by student_classification", {
  # Filter to HIST 1110 only (registered students)
  filtered <- known_students %>%
    filter(registration_status_code %in% c("RE", "RS"),
           subject_course == "HIST 1110")

  opt <- list(group_cols = c("campus", "college", "term", "term_type",
                             "student_classification", "subject_course"))

  result <- summarize_student_demographics(filtered, opt)

  # Should have student_classification column
  expect_true("student_classification" %in% colnames(result))

  # Known: HIST 1110 has 4 registered students, all Freshman
  expect_equal(sum(result$count), 4)
})

test_that("summarize_student_demographics groups by major", {
  # Filter to MATH 1215 (registered students only)
  filtered <- known_students %>%
    filter(registration_status_code %in% c("RE", "RS"),
           subject_course == "MATH 1215")

  opt <- list(group_cols = c("campus", "college", "term", "term_type",
                             "major", "subject_course"))

  result <- summarize_student_demographics(filtered, opt)

  # Should have major column
  expect_true("major" %in% colnames(result))

  # Known: MATH 1215 has 4 registered students (1 is DR)
  # 4 registered: STU009-STU012 (all Mathematics majors)
  expect_equal(sum(result$count), 4)
})

test_that("summarize_student_demographics calculates percentages correctly", {
  # Filter to a course with multiple classifications
  filtered <- known_students %>%
    filter(registration_status_code %in% c("RE", "RS"),
           subject_course == "ANTH 1110")

  opt <- list(group_cols = c("campus", "college", "term", "term_type",
                             "student_classification", "subject_course"))

  result <- summarize_student_demographics(filtered, opt)

  # term_pct should sum to 100 (or close) for each term
  term_pcts <- result %>%
    group_by(term) %>%
    summarize(total_pct = sum(term_pct), .groups = "drop")

  # Each term should have percentages summing to ~100
  expect_true(all(abs(term_pcts$total_pct - 100) < 1))
})


# =============================================================================
# rollcall() tests - main orchestrating function
# =============================================================================

test_that("rollcall returns correct structure", {
  opt <- create_test_opt(list(course = "HIST 1110"))

  result <- rollcall(known_students, opt)

  expect_s3_class(result, "data.frame")
  expect_true("count" %in% colnames(result))
  expect_true("mean" %in% colnames(result))
  expect_true("term_pct" %in% colnames(result))
})

test_that("rollcall filters by course correctly", {
  opt <- create_test_opt(list(course = "HIST 1110"))

  result <- rollcall(known_students, opt)

  # Should only have HIST 1110 in results
  expect_true(all(result$subject_course == "HIST 1110"))
})

test_that("rollcall filters by term correctly", {
  opt <- create_test_opt(list(term = 202510))

  result <- rollcall(known_students, opt)

  # Should only have term 202510 in results
  expect_true(all(result$term == 202510))
})

test_that("rollcall filters by department correctly", {
  opt <- create_test_opt(list(dept = "HIST"))

  result <- rollcall(known_students, opt)

  # All results should be HIST courses
  expect_true(all(grepl("^HIST", result$subject_course)))
})

test_that("rollcall excludes early drops by default", {
  # HIST 1120 has 5 students but 1 is DR (early drop)
  opt <- create_test_opt(list(course = "HIST 1120"))

  result <- rollcall(known_students, opt)

  # Should count 4 students, not 5 (excludes the DR)
  total_count <- sum(result$count)
  expect_equal(total_count, 4)
})

test_that("rollcall removes pre-201980 data", {
  # Create test data with some pre-2019 terms
  # Modify rows 1-2 (HIST 1110) to 201910, leaving rows 3-4 at 202510
  old_students <- known_students %>%
    mutate(term = ifelse(row_number() <= 2, 201910, term))

  opt <- create_test_opt(list(course = "HIST 1110"))

  result <- rollcall(old_students, opt)

  # HIST 1110 originally has 4 students in term 202510
  # After modifying 2 to 201910, only 2 remain in 202510
  # Pre-201980 data should be filtered out
  expect_true(all(result$term >= 201980))
  # Should have 2 students (the ones still at 202510)
  expect_equal(sum(result$count), 2)
})

test_that("rollcall uses default group_cols when not specified", {
  opt <- create_test_opt(list(course = "HIST 1110"))

  result <- rollcall(known_students, opt)

  # Default group_cols include student_classification
  expect_true("student_classification" %in% colnames(result))
  # And major
  expect_true("major" %in% colnames(result))
})

test_that("rollcall uses custom group_cols when specified", {
  opt <- create_test_opt(list(
    course = "HIST 1110",
    group_cols = c("campus", "college", "term", "term_type",
                   "student_classification", "subject_course")
  ))

  result <- rollcall(known_students, opt)

  # Should have student_classification but NOT major
  expect_true("student_classification" %in% colnames(result))
  expect_false("major" %in% colnames(result))
})


# =============================================================================
# calc_cl_enrls() integration tests
# =============================================================================

test_that("calc_cl_enrls returns enrollment counts", {
  filtered <- known_students %>%
    filter(registration_status_code %in% c("RE", "RS"),
           subject_course == "HIST 1110")

  result <- calc_cl_enrls(filtered)

  expect_s3_class(result, "data.frame")
  expect_true("registered" %in% colnames(result))
  expect_true("registered_mean" %in% colnames(result))

  # HIST 1110 should have 4 registered students
  expect_equal(result$registered[1], 4)
})

test_that("calc_cl_enrls handles multiple courses", {
  filtered <- known_students %>%
    filter(registration_status_code %in% c("RE", "RS"),
           department == "HIST")

  result <- calc_cl_enrls(filtered)

  # Should have rows for multiple HIST courses
  expect_true(nrow(result) >= 2)
  expect_true("HIST 1110" %in% result$subject_course)
  expect_true("HIST 1120" %in% result$subject_course)
})


# =============================================================================
# Edge cases and validation
# =============================================================================

test_that("rollcall handles empty result gracefully", {
  # Filter for a course that doesn't exist
  opt <- create_test_opt(list(course = "NONEXISTENT 9999"))

  result <- rollcall(known_students, opt)

  expect_equal(nrow(result), 0)
  expect_true(is.data.frame(result))
})

test_that("rollcall handles multiple filter criteria", {
  opt <- create_test_opt(list(
    dept = "HIST",
    term = 202510
  ))

  result <- rollcall(known_students, opt)

  # Should have HIST courses in 202510 only
  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_true(all(result$term == 202510))
})


# =============================================================================
# Specific known value tests
# =============================================================================

test_that("rollcall returns correct counts for HIST 1110 classifications", {
  opt <- create_test_opt(list(
    course = "HIST 1110",
    group_cols = c("campus", "college", "term", "term_type",
                   "student_classification", "subject_course")
  ))

  result <- rollcall(known_students, opt)

  # Known: HIST 1110 has 4 registered students, all Freshman
  freshman_count <- result %>%
    filter(student_classification == "Freshman") %>%
    pull(count) %>%
    sum()

  expect_equal(freshman_count, 4)
})

test_that("rollcall returns correct counts for MATH 1215 majors", {
  opt <- create_test_opt(list(
    course = "MATH 1215",
    group_cols = c("campus", "college", "term", "term_type",
                   "major", "subject_course")
  ))

  result <- rollcall(known_students, opt)

  # Known: MATH 1215 has 4 registered students (5 total, 1 DR)
  # All 4 registered are Mathematics majors
  math_major_count <- result %>%
    filter(major == "Mathematics") %>%
    pull(count) %>%
    sum()

  expect_equal(math_major_count, 4)
})

test_that("rollcall returns correct counts across all ANTH courses", {
  opt <- create_test_opt(list(
    dept = "ANTH",
    group_cols = c("campus", "college", "term", "term_type",
                   "subject_course", "student_classification")
  ))

  result <- rollcall(known_students, opt)

  # Known: ANTH has 6 enrollments total
  # ANTH 1110: 4 students (202510) - Junior
  # ANTH 2050: 2 students (202580) - Senior
  total_count <- sum(result$count)
  expect_equal(total_count, 6)
})
