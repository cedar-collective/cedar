# Tests for grade analysis functions
# Tests R/cones/gradebook.R helper functions
#
# Uses known_students fixture from fixtures/known_test_data.R
# See fixture file for expected DFW calculation values

# Source required functions
source("../../R/branches/filter.R")  # for convert_param_to_list
source("../../R/lists/grades.R")     # for grades_to_points, passing_grades
source("../../R/cones/gradebook.R")

context("Grade Analysis")

# =============================================================================
# Helper to prepare grade_counts structure from known_students
# =============================================================================
# The gradebook expects grade_counts as a data frame with:
# campus, college, term, subject_course, instructor_last_name, final_grade, count

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
  result <- count_grades(known_students, group_cols)

  expect_s3_class(result, "data.frame")
  expect_true("count" %in% names(result))
  expect_true("final_grade" %in% names(result))
  expect_true(all(group_cols %in% names(result)))
})

test_that("count_grades counts grades correctly for HIST 1110", {
  # Filter to HIST 1110 term 202510 to test specific counts
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1110", term == 202510)

  group_cols <- c("campus", "term", "subject_course")
  result <- count_grades(hist_students, group_cols)

  # HIST 1110 has: A=1, B=1, F=1, W=1 (4 students total)
  expect_equal(sum(result$count), 4)

  # Check specific grade counts
  a_count <- result %>% filter(final_grade == "A") %>% pull(count)
  expect_equal(a_count, 1)

  f_count <- result %>% filter(final_grade == "F") %>% pull(count)
  expect_equal(f_count, 1)
})

test_that("count_grades handles empty input", {
  empty_students <- known_students %>% filter(student_id == "NONEXISTENT")
  result <- count_grades(empty_students, c("campus", "term"))

  expect_equal(nrow(result), 0)
})


# =============================================================================
# categorize_grades() tests
# =============================================================================

# Define passing grades for tests
# Note: D is excluded for proper DFW semantics (D, F, W are all "failing" in DFW calculation)
test_passing_grades <- c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "S", "CR")

test_that("categorize_grades returns correct structure", {
  # Prepare grade counts for testing
  grade_counts <- prepare_grade_counts(known_students)
  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")

  result <- categorize_grades(grade_counts, group_cols, test_passing_grades)

  expect_s3_class(result, "data.frame")
  expect_true("passed" %in% names(result))
  expect_true("failed" %in% names(result))
  expect_true("early_dropped" %in% names(result))
  expect_true("late_dropped" %in% names(result))
})

test_that("categorize_grades counts passed grades correctly", {
  # Filter to HIST 1110 (2 passing: A, B)
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1110", term == 202510)

  grade_counts <- hist_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  result <- categorize_grades(grade_counts, group_cols, test_passing_grades)

  expect_equal(result$passed, 2)  # A and B are passing
})

test_that("categorize_grades counts failed grades correctly (excludes early drops)", {
  # Filter to HIST 1110 (2 failing: F, W)
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1110", term == 202510)

  grade_counts <- hist_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  result <- categorize_grades(grade_counts, group_cols, test_passing_grades)

  expect_equal(result$failed, 2)  # F and W are failed (W is late drop but counted as failed)
})

test_that("categorize_grades counts late drops (W) correctly", {
  # HIST 1110 has 1 W grade (late drop)
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1110", term == 202510)

  grade_counts <- hist_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  result <- categorize_grades(grade_counts, group_cols, test_passing_grades)

  expect_equal(result$late_dropped, 1)
})

test_that("categorize_grades counts early drops (Drop) correctly", {
  # HIST 1120 has 1 Drop grade (early drop from DR status)
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1120", term == 202510)

  grade_counts <- hist_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  result <- categorize_grades(grade_counts, group_cols, test_passing_grades)

  expect_equal(result$early_dropped, 1)
})

test_that("categorize_grades handles empty input", {
  empty_counts <- data.frame()
  result <- categorize_grades(empty_counts, c("campus", "term"), test_passing_grades)

  expect_equal(nrow(result), 0)
})


# =============================================================================
# calculate_dfw() tests
# =============================================================================

test_that("calculate_dfw returns correct structure", {
  categorized <- tibble(
    campus = "Main",
    term = 202510,
    passed = 10,
    failed = 5,
    early_dropped = 2,
    late_dropped = 3
  )

  result <- calculate_dfw(categorized)

  expect_s3_class(result, "data.frame")
  expect_true("dfw_pct" %in% names(result))
})

test_that("calculate_dfw computes DFW percentage correctly", {
  # dfw_pct = failed / (passed + failed) * 100
  categorized <- tibble(
    campus = "Main",
    term = 202510,
    passed = 8,
    failed = 2,
    early_dropped = 1,
    late_dropped = 1
  )

  result <- calculate_dfw(categorized)

  # dfw_pct = 2 / (8 + 2) * 100 = 20%
  expect_equal(result$dfw_pct, 20)
})

test_that("calculate_dfw excludes early drops from calculation", {
  # Early drops should NOT affect the DFW calculation
  categorized <- tibble(
    campus = "Main",
    term = 202510,
    passed = 8,
    failed = 2,
    early_dropped = 10,  # These should be ignored
    late_dropped = 1
  )

  result <- calculate_dfw(categorized)

  # dfw_pct should still be 2 / (8 + 2) * 100 = 20%
  # early_dropped is NOT added to denominator
  expect_equal(result$dfw_pct, 20)
})

test_that("calculate_dfw handles 0% DFW (all passed)", {
  categorized <- tibble(
    campus = "Main",
    term = 202510,
    passed = 10,
    failed = 0,
    early_dropped = 0,
    late_dropped = 0
  )

  result <- calculate_dfw(categorized)

  expect_equal(result$dfw_pct, 0)
})

test_that("calculate_dfw handles 100% DFW (all failed)", {
  categorized <- tibble(
    campus = "Main",
    term = 202510,
    passed = 0,
    failed = 10,
    early_dropped = 0,
    late_dropped = 5
  )

  result <- calculate_dfw(categorized)

  expect_equal(result$dfw_pct, 100)
})

test_that("calculate_dfw handles empty input", {
  empty_categorized <- data.frame()
  result <- calculate_dfw(empty_categorized)

  expect_equal(nrow(result), 0)
})


# =============================================================================
# Integration test: Full DFW pipeline with known_students
# =============================================================================

test_that("DFW pipeline calculates correct percentages for HIST 1110", {
  # HIST 1110: passed=2, failed=2, early_dropped=0 -> dfw_pct = 50%
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1110", term == 202510)

  grade_counts <- hist_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  categorized <- categorize_grades(grade_counts, group_cols, test_passing_grades)
  result <- calculate_dfw(categorized)

  expect_equal(result$dfw_pct, 50)
})

test_that("DFW pipeline calculates correct percentages for HIST 1120", {
  # HIST 1120: passed=2, failed=2, early_dropped=1 -> dfw_pct = 50%
  hist_students <- known_students %>%
    filter(subject_course == "HIST 1120", term == 202510)

  grade_counts <- hist_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  categorized <- categorize_grades(grade_counts, group_cols, test_passing_grades)
  result <- calculate_dfw(categorized)

  expect_equal(result$dfw_pct, 50)
  expect_equal(result$early_dropped, 1)  # Verify early drop was counted separately
})

test_that("DFW pipeline calculates correct percentages for MATH 1215", {
  # MATH 1215: passed=3, failed=1, early_dropped=1 -> dfw_pct = 25%
  math_students <- known_students %>%
    filter(subject_course == "MATH 1215", term == 202510)

  grade_counts <- math_students %>%
    filter(!is.na(final_grade)) %>%
    group_by(campus, college, term, subject_course, instructor_last_name, final_grade) %>%
    summarize(count = n(), .groups = "keep")

  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  categorized <- categorize_grades(grade_counts, group_cols, test_passing_grades)
  result <- calculate_dfw(categorized)

  expect_equal(result$dfw_pct, 25)
})


# =============================================================================
# aggregate_grades() tests
# =============================================================================

test_that("aggregate_grades returns correct structure", {
  dfw_summary <- tibble(
    campus = c("Main", "Main"),
    college = c("AS", "AS"),
    term = c(202510, 202510),
    subject_course = c("HIST 1110", "HIST 1120"),
    passed = c(10, 8),
    failed = c(5, 4),
    early_dropped = c(2, 1),
    late_dropped = c(3, 2)
  )

  opt <- list(group_cols = c("campus", "college"))
  result <- aggregate_grades(dfw_summary, opt)

  expect_s3_class(result, "data.frame")
  expect_true("passed" %in% names(result))
  expect_true("failed" %in% names(result))
  expect_true("dfw_pct" %in% names(result))
})

test_that("aggregate_grades sums values across groups", {
  dfw_summary <- tibble(
    campus = c("Main", "Main"),
    college = c("AS", "AS"),
    term = c(202510, 202510),
    subject_course = c("HIST 1110", "HIST 1120"),
    passed = c(10, 8),
    failed = c(5, 4),
    early_dropped = c(2, 1),
    late_dropped = c(3, 2)
  )

  # Group by campus only (should sum both courses)
  opt <- list(group_cols = c("campus"))
  result <- aggregate_grades(dfw_summary, opt)

  expect_equal(result$passed, 18)  # 10 + 8
  expect_equal(result$failed, 9)   # 5 + 4
  expect_equal(result$early_dropped, 3)  # 2 + 1
  expect_equal(result$late_dropped, 5)   # 3 + 2
})

test_that("aggregate_grades calculates dfw_pct after aggregation", {
  dfw_summary <- tibble(
    campus = c("Main", "Main"),
    college = c("AS", "AS"),
    term = c(202510, 202510),
    subject_course = c("HIST 1110", "HIST 1120"),
    passed = c(10, 10),  # Total: 20
    failed = c(5, 5),    # Total: 10
    early_dropped = c(0, 0),
    late_dropped = c(0, 0)
  )

  opt <- list(group_cols = c("campus"))
  result <- aggregate_grades(dfw_summary, opt)

  # Aggregated dfw_pct = 10 / (20 + 10) * 100 = 33.33%
  expect_equal(result$dfw_pct, 33.33)
})

test_that("aggregate_grades handles missing columns gracefully", {
  dfw_summary <- tibble(
    campus = c("Main"),
    college = c("AS"),
    passed = c(10),
    failed = c(5),
    early_dropped = c(2),
    late_dropped = c(3)
  )

  # Request a column that doesn't exist
  opt <- list(group_cols = c("campus", "nonexistent_column"))

  # Should warn but not fail, using only available columns
  expect_message(
    result <- aggregate_grades(dfw_summary, opt),
    "WARNING"
  )

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
})

test_that("aggregate_grades handles empty input", {
  empty_summary <- data.frame()
  opt <- list(group_cols = c("campus"))
  result <- aggregate_grades(empty_summary, opt)

  expect_equal(nrow(result), 0)
})


# =============================================================================
# prepare_students_for_grading() tests
# =============================================================================
# Note: These tests focus on the transformation logic (DR->Drop, deduplication, term filter)
# The filter_class_list integration is tested via the main get_grades() function

test_that("DR registration status converts to Drop grade (logic verification)", {
  # Verify the logic used in prepare_students_for_grading:
  # final_grade = ifelse(registration_status_code == "DR", "Drop", final_grade)

  test_data <- tibble(
    registration_status_code = c("RE", "DR", "RE", "DR"),
    final_grade = c("A", "B", "F", "C")
  )

  result <- test_data %>%
    mutate(final_grade = ifelse(registration_status_code == "DR", "Drop", final_grade))

  expect_equal(result$final_grade, c("A", "Drop", "F", "Drop"))
})

test_that("Deduplication by student_id, campus, college, crn works (logic verification)", {
  # Verify the distinct() logic used in prepare_students_for_grading

  test_data <- tibble(
    student_id = c("S1", "S1", "S2", "S2"),
    campus = c("Main", "Main", "Main", "Online"),
    college = c("AS", "AS", "AS", "AS"),
    crn = c(10001, 10001, 10001, 10001),  # S1 duplicate in same section
    grade = c("A", "A-", "B", "C")  # Different grades for duplicates
  )

  result <- test_data %>%
    distinct(student_id, campus, college, crn, .keep_all = TRUE)

  # S1 on Main/AS/10001 should appear once, S2 on Main and Online are different
  expect_equal(nrow(result), 3)
  expect_equal(sum(result$student_id == "S1"), 1)
})

test_that("Term filter >= 201980 works (logic verification)", {
  # Verify the term filter logic used in prepare_students_for_grading

  test_data <- tibble(
    term = c(201910, 201980, 202010, 202510),
    student = c("A", "B", "C", "D")
  )

  result <- test_data %>% filter(term >= 201980)

  expect_equal(nrow(result), 3)
  expect_false(201910 %in% result$term)
  expect_true(all(result$term >= 201980))
})

test_that("grades_to_points lookup exists and has expected structure", {
  # Verify the grades_to_points table is available and correct
  expect_true(exists("grades_to_points"))
  expect_true("grade" %in% names(grades_to_points))
  expect_true("points" %in% names(grades_to_points))

  # Check key grades are present
  expect_true("A" %in% grades_to_points$grade)
  expect_true("F" %in% grades_to_points$grade)
  expect_true("Drop" %in% grades_to_points$grade)
  expect_true("W" %in% grades_to_points$grade)
})


# =============================================================================
# merge_faculty_data() tests
# =============================================================================

test_that("merge_faculty_data adds job_category column", {
  grade_counts <- tibble(
    instructor_id = c("INS001", "INS002"),
    term = c(202510, 202510),
    campus = "Main",
    college = "AS",
    subject_course = "HIST 1110",
    final_grade = c("A", "B"),
    count = c(5, 3)
  )

  faculty <- tibble(
    instructor_id = c("INS001", "INS002"),
    term = c(202510, 202510),
    job_category = c("TT", "NTT")
  )

  result <- merge_faculty_data(grade_counts, faculty)

  expect_true("job_category" %in% names(result))
  expect_equal(nrow(result), 2)
})

test_that("merge_faculty_data returns original data when no matches", {
  grade_counts <- tibble(
    instructor_id = c("INS999"),  # Non-existent instructor
    term = c(202510),
    campus = "Main",
    college = "AS",
    subject_course = "HIST 1110",
    final_grade = c("A"),
    count = c(5)
  )

  faculty <- tibble(
    instructor_id = c("INS001"),
    term = c(202510),
    job_category = c("TT")
  )

  result <- merge_faculty_data(grade_counts, faculty)

  # Should return original data without job_category
  expect_equal(nrow(result), 1)
  expect_false("job_category" %in% names(result))
})

test_that("merge_faculty_data matches by both instructor_id AND term", {
  grade_counts <- tibble(
    instructor_id = c("INS001", "INS001"),
    term = c(202510, 202580),  # Same instructor, different terms
    campus = "Main",
    college = "AS",
    subject_course = "HIST 1110",
    final_grade = c("A", "B"),
    count = c(5, 3)
  )

  # Faculty data only has INS001 for term 202510
  faculty <- tibble(
    instructor_id = c("INS001"),
    term = c(202510),
    job_category = c("TT")
  )

  result <- merge_faculty_data(grade_counts, faculty)

  # Only the matching term should have job_category
  # If merge fails for one, returns original (without job_category)
  expect_equal(nrow(result), 1)  # Only one match
  expect_equal(result$term, 202510)
})


# =============================================================================
# build_aggregation_list() tests
# =============================================================================

test_that("build_aggregation_list returns all expected tables", {
  dfw_summary <- tibble(
    campus = c("Main", "Main"),
    college = c("AS", "AS"),
    term = c(202510, 202580),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Jones"),
    job_category = c("TT", "NTT"),
    passed = c(10, 8),
    failed = c(5, 4),
    early_dropped = c(2, 1),
    late_dropped = c(3, 2)
  )

  grade_counts <- tibble(
    campus = c("Main", "Main"),
    term = c(202510, 202580),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Jones"),
    final_grade = c("A", "B"),
    count = c(5, 3)
  )

  result <- build_aggregation_list(dfw_summary, grade_counts)

  # Check all expected tables are present
  expect_true("course_inst_avg" %in% names(result))
  expect_true("inst_type" %in% names(result))
  expect_true("course_term" %in% names(result))
  expect_true("course_avg" %in% names(result))
  expect_true("course_avg_by_term" %in% names(result))
})

test_that("build_aggregation_list includes sections_taught in course_inst_avg", {
  dfw_summary <- tibble(
    campus = c("Main", "Main"),
    college = c("AS", "AS"),
    term = c(202510, 202580),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Smith"),  # Same instructor, 2 terms
    passed = c(10, 8),
    failed = c(5, 4),
    early_dropped = c(2, 1),
    late_dropped = c(3, 2)
  )

  grade_counts <- tibble(
    campus = c("Main", "Main"),
    term = c(202510, 202580),
    subject_course = c("HIST 1110", "HIST 1110"),
    instructor_last_name = c("Smith", "Smith"),
    final_grade = c("A", "B"),
    count = c(5, 3)
  )

  result <- build_aggregation_list(dfw_summary, grade_counts)

  # course_inst_avg should have sections_taught column
  expect_true("sections_taught" %in% names(result$course_inst_avg))

  # Smith taught 2 sections (2 different terms)
  smith_data <- result$course_inst_avg %>% filter(instructor_last_name == "Smith")
  expect_equal(smith_data$sections_taught, 2)
})
