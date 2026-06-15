# Tests for grade analysis functions
# Tests R/branches/gradebook.R helper functions
#
# Uses test_students (cedar_students_test.qs).
# Inline tibbles used only for pure-logic functions (calculate_dfw formula,
# aggregate_grades math, merge joins) — not for CEDAR data structure tests.
#
# Reference values (from running against fixtures, HIST 1110 term 202010):
#   count_grades: W=9, A=3
#   categorize_grades: passed=17, failed=4, early_dropped=0, late_dropped=9
#   calculate_dfw: 43.33%  ((4+9) / (17+4+9) * 100)

context("Grade Analysis")

# Helper: build grade_counts structure for use in categorize_grades tests
prepare_grade_counts <- function(students) {
  students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")
}


# =============================================================================
# count_grades() tests
# =============================================================================

test_that("count_grades returns correct structure", {
  group_cols <- c("campus", "term", "subject_course")
  result     <- count_grades(test_students, group_cols)

  expect_s3_class(result, "data.frame")
  expect_true("count"       %in% names(result))
  expect_true("final_grade" %in% names(result))
  expect_true(all(group_cols %in% names(result)))
})

test_that("count_grades counts W and A grades correctly for HIST 1110 term 202010", {
  hist_students <- test_students %>%
    filter(subject_course == "HIST 1110", term == 202010)

  group_cols <- c("campus", "term", "subject_course")
  result     <- count_grades(hist_students, group_cols)

  expect_equal(sum(result$count[result$final_grade == "W"], na.rm = TRUE), 9)
  expect_equal(sum(result$count[result$final_grade == "A"], na.rm = TRUE), 3)
})

test_that("count_grades handles empty input", {
  empty  <- test_students %>% filter(student_id == "NONEXISTENT")
  result <- count_grades(empty, c("campus", "term"))

  expect_equal(nrow(result), 0)
})


# =============================================================================
# categorize_grades() tests
# =============================================================================

test_that("categorize_grades returns correct structure", {
  grade_counts <- prepare_grade_counts(
    test_students %>% filter(subject_course == "HIST 1110", term == 202010)
  )
  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")

  result <- categorize_grades(grade_counts, group_cols, GRADES_PASS)

  expect_s3_class(result, "data.frame")
  expect_true("passed"        %in% names(result))
  expect_true("failed"        %in% names(result))
  expect_true("early_dropped" %in% names(result))
  expect_true("late_dropped"  %in% names(result))
})

test_that("categorize_grades counts pass/fail/drop correctly for HIST 1110 202010", {
  grade_counts <- prepare_grade_counts(
    test_students %>% filter(subject_course == "HIST 1110", term == 202010)
  )
  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")

  result <- categorize_grades(grade_counts, group_cols, GRADES_PASS)

  # HIST 1110 202010: 17 pass, 4 non-W fail, 0 early drops, 9 late drops
  expect_equal(sum(result$passed),        17)
  expect_equal(sum(result$failed),         4)
  expect_equal(sum(result$early_dropped),  0)
  expect_equal(sum(result$late_dropped),   9)
})

test_that("categorize_grades handles empty input", {
  result <- categorize_grades(data.frame(), c("campus", "term"), GRADES_PASS)
  expect_equal(nrow(result), 0)
})


# =============================================================================
# calculate_dfw() tests — inline tibbles testing mathematical formula
# =============================================================================

test_that("calculate_dfw returns correct structure", {
  categorized <- tibble(
    campus = "GA", term = 202010, passed = 10, failed = 5,
    early_dropped = 2, late_dropped = 3
  )
  result <- calculate_dfw(categorized)

  expect_s3_class(result, "data.frame")
  expect_true("dfw_pct" %in% names(result))
})

test_that("calculate_dfw computes dfw_pct = (failed + late_dropped) / denominator * 100", {
  categorized <- tibble(
    campus = "GA", term = 202010, passed = 8, failed = 2,
    early_dropped = 1, late_dropped = 1
  )
  expect_equal(calculate_dfw(categorized)$dfw_pct, 27.27)
})

test_that("calculate_dfw excludes early drops from denominator", {
  categorized <- tibble(
    campus = "GA", term = 202010, passed = 8, failed = 2,
    early_dropped = 10, late_dropped = 1
  )
  # (2+1)/(8+2+1)*100 = 27.27%, early_dropped NOT in denominator
  expect_equal(calculate_dfw(categorized)$dfw_pct, 27.27)
})

test_that("calculate_dfw handles 0% DFW (all passed)", {
  categorized <- tibble(
    campus = "GA", term = 202010, passed = 10, failed = 0,
    early_dropped = 0, late_dropped = 0
  )
  expect_equal(calculate_dfw(categorized)$dfw_pct, 0)
})

test_that("calculate_dfw handles 100% DFW (all failed)", {
  categorized <- tibble(
    campus = "GA", term = 202010, passed = 0, failed = 10,
    early_dropped = 0, late_dropped = 5
  )
  expect_equal(calculate_dfw(categorized)$dfw_pct, 100)
})

test_that("calculate_dfw handles empty input", {
  expect_equal(nrow(calculate_dfw(data.frame())), 0)
})


# =============================================================================
# Integration: full DFW pipeline with test_students
# =============================================================================

test_that("DFW pipeline gives 43.33% for HIST 1110 term 202010", {
  # passed=17, failed=4, late_dropped=9, dfw_pct = 13/30*100 = 43.33%
  hist_students <- test_students %>%
    filter(subject_course == "HIST 1110", term == 202010)

  grade_counts <- prepare_grade_counts(hist_students)
  group_cols   <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  categorized  <- categorize_grades(grade_counts, group_cols, GRADES_PASS)
  result       <- calculate_dfw(categorized)

  expect_equal(sum(result$dfw_pct), 43.33)
})


# =============================================================================
# aggregate_grades() tests — inline tibbles testing aggregation logic
# =============================================================================

test_that("aggregate_grades returns correct structure", {
  dfw_summary <- tibble(
    campus = c("GA", "GA"), college = c("AS", "AS"), term = c(202010, 202010),
    subject_course = c("HIST 1110", "HIST 1120"),
    passed = c(10, 8), failed = c(5, 4), early_dropped = c(2, 1), late_dropped = c(3, 2)
  )
  result <- aggregate_grades(dfw_summary, list(group_cols = c("campus", "college")))

  expect_s3_class(result, "data.frame")
  expect_true("passed"  %in% names(result))
  expect_true("failed"  %in% names(result))
  expect_true("dfw_pct" %in% names(result))
})

test_that("aggregate_grades sums correctly across two courses", {
  dfw_summary <- tibble(
    campus = c("GA", "GA"), college = c("AS", "AS"), term = c(202010, 202010),
    subject_course = c("HIST 1110", "HIST 1120"),
    passed = c(10, 8), failed = c(5, 4), early_dropped = c(2, 1), late_dropped = c(3, 2)
  )
  result <- aggregate_grades(dfw_summary, list(group_cols = c("campus")))

  expect_equal(result$passed,        18)
  expect_equal(result$failed,         9)
  expect_equal(result$early_dropped,  3)
  expect_equal(result$late_dropped,   5)
})

test_that("aggregate_grades recalculates dfw_pct after aggregation", {
  dfw_summary <- tibble(
    campus = c("GA", "GA"), college = c("AS", "AS"), term = c(202010, 202010),
    subject_course = c("HIST 1110", "HIST 1120"),
    passed = c(10, 10), failed = c(5, 5), early_dropped = c(0, 0), late_dropped = c(0, 0)
  )
  result <- aggregate_grades(dfw_summary, list(group_cols = c("campus")))

  # 10 / (20+10) * 100 = 33.33%
  expect_equal(result$dfw_pct, 33.33)
})

test_that("aggregate_grades handles empty input", {
  expect_equal(nrow(aggregate_grades(data.frame(), list(group_cols = c("campus")))), 0)
})


# =============================================================================
# grades_to_points lookup
# =============================================================================

test_that("grades_to_points exists with expected structure and key entries", {
  expect_true(exists("grades_to_points"))
  expect_true("grade"  %in% names(grades_to_points))
  expect_true("points" %in% names(grades_to_points))

  expect_true("A"    %in% grades_to_points$grade)
  expect_true("F"    %in% grades_to_points$grade)
  expect_true("Drop" %in% grades_to_points$grade)
  expect_true("W"    %in% grades_to_points$grade)
})


# =============================================================================
# merge_faculty_data() tests — inline tibbles testing join logic
# =============================================================================

test_that("merge_faculty_data adds job_category column", {
  grade_counts <- tibble(
    instructor_id = c("INS001", "INS002"), term = c(202010, 202010),
    campus = "GA", college = "AS", subject_course = "HIST 1110",
    final_grade = c("A", "B"), count = c(5, 3)
  )
  faculty <- tibble(
    instructor_id = c("INS001", "INS002"), term = c(202010, 202010),
    job_category = c("TT", "NTT")
  )
  result <- merge_faculty_data(grade_counts, faculty)

  expect_true("job_category" %in% names(result))
  expect_equal(nrow(result), 2)
})

test_that("merge_faculty_data sets job_category NA when no match", {
  grade_counts <- tibble(
    instructor_id = "INS999", term = 202010,
    campus = "GA", college = "AS", subject_course = "HIST 1110",
    final_grade = "A", count = 5
  )
  faculty <- tibble(instructor_id = "INS001", term = 202010, job_category = "TT")

  result <- merge_faculty_data(grade_counts, faculty)
  expect_equal(nrow(result), 1)
  expect_true(is.na(result$job_category))
})

test_that("merge_faculty_data matches by both instructor_id and term", {
  grade_counts <- tibble(
    instructor_id = c("INS001", "INS001"), term = c(202010, 202080),
    campus = "GA", college = "AS", subject_course = "HIST 1110",
    final_grade = c("A", "B"), count = c(5, 3)
  )
  faculty <- tibble(instructor_id = "INS001", term = 202010, job_category = "TT")

  result <- merge_faculty_data(grade_counts, faculty)
  expect_equal(nrow(result), 2)
  expect_equal(result$job_category[result$term == 202010], "TT")
  expect_true(is.na(result$job_category[result$term == 202080]))
})


# =============================================================================
# build_aggregation_list() tests
# =============================================================================

test_that("build_aggregation_list returns expected table keys", {
  dfw_summary <- tibble(
    campus = c("GA", "GA"), college = c("AS", "AS"), term = c(202010, 202080),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Jones"), job_category = c("TT", "NTT"),
    passed = c(10, 8), failed = c(5, 4), early_dropped = c(2, 1), late_dropped = c(3, 2)
  )
  grade_counts <- tibble(
    campus = c("GA", "GA"), term = c(202010, 202080),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Jones"),
    final_grade = c("A", "B"), count = c(5, 3)
  )
  result <- build_aggregation_list(dfw_summary, grade_counts)

  expect_true("course_inst_avg"    %in% names(result))
  expect_true("course_term"        %in% names(result))
  expect_true("course_avg"         %in% names(result))
  expect_true("course_avg_by_term" %in% names(result))
  expect_false("inst_type"         %in% names(result))
})

test_that("build_aggregation_list includes sections_taught in course_inst_avg", {
  dfw_summary <- tibble(
    campus = c("GA", "GA"), college = c("AS", "AS"), term = c(202010, 202080),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Smith"),
    passed = c(10, 8), failed = c(5, 4), early_dropped = c(2, 1), late_dropped = c(3, 2)
  )
  grade_counts <- tibble(
    campus = c("GA", "GA"), term = c(202010, 202080),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Smith"),
    final_grade = c("A", "B"), count = c(5, 3)
  )
  result <- build_aggregation_list(dfw_summary, grade_counts)

  expect_true("sections_taught" %in% names(result$course_inst_avg))
  smith_row <- result$course_inst_avg %>% filter(instructor_last_name == "Smith")
  expect_equal(smith_row$sections_taught, 2)
})
