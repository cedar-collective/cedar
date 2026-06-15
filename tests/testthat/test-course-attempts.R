context("Course Attempts and Outcome APIs")


test_that("prepare_course_attempts normalizes drops, excludes audits, and deduplicates", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  designed <- dplyr::bind_rows(
    base_row %>% dplyr::mutate(
      student_id = "attempt-dr", crn = "91001",
      registration_status_code = "DR", final_grade = NA_character_
    ),
    base_row %>% dplyr::mutate(
      student_id = "attempt-dw", crn = "91002",
      registration_status_code = "DW", final_grade = NA_character_
    ),
    base_row %>% dplyr::mutate(
      student_id = "attempt-aud", crn = "91003",
      registration_status_code = "DG", final_grade = "AUD"
    ),
    base_row %>% dplyr::mutate(
      student_id = "attempt-dup", crn = "91004",
      registration_status_code = "RE", final_grade = "A"
    ),
    base_row %>% dplyr::mutate(
      student_id = "attempt-dup", crn = "91004",
      registration_status_code = "RE", final_grade = "A"
    )
  )

  result <- prepare_course_attempts(designed, opt = list(course = "HIST 1110"))

  expect_false("attempt-aud" %in% result$student_id)
  expect_equal(result$final_grade[result$student_id == "attempt-dr"], "Drop")
  expect_equal(result$final_grade[result$student_id == "attempt-dw"], "W")
  expect_equal(sum(result$student_id == "attempt-dup"), 1L)
  expect_true("final_grade_raw" %in% names(result))
})


test_that("get_course_outcome_rates exposes nuanced DFW components", {
  result <- get_course_outcome_rates(
    test_students,
    opt = list(course = "HIST 1110"),
    group_cols = "subject_course",
    min_n = 1L
  )

  expect_equal(nrow(result), 1L)
  expect_true(all(c(
    "n_attempts", "n_pass", "n_c_minus", "n_d", "n_f", "n_w",
    "n_early_drop", "dfw_pct", "w_pct", "df_pct", "below_c_pct"
  ) %in% names(result)))
  expect_equal(result$subject_course, "HIST 1110")
  expect_gte(result$n_attempts, result$n_pass)
})


test_that("get_grade_distribution returns counts and percentages", {
  result <- get_grade_distribution(
    test_students,
    opt = list(course = "HIST 1110"),
    group_cols = "subject_course",
    min_n = 1L
  )

  expect_equal(nrow(result), 1L)
  expect_true(all(c("A", "B", "C", "D", "F", "W", "Other", "total") %in% names(result)))
  expect_true(all(c("A_pct", "B_pct", "C_pct", "D_pct", "F_pct", "W_pct", "Other_pct") %in% names(result)))
  expect_equal(result$total, sum(unlist(result[, c("A", "B", "C", "D", "F", "W", "Other")])))
})


test_that("new outcome API matches legacy get_grades course averages", {
  legacy <- get_grades(test_students, list(course = "HIST 1110"))$course_avg %>%
    dplyr::arrange(campus, college, subject_course) %>%
    dplyr::select(campus, college, subject_course, dfw_pct)

  modern <- get_course_outcome_rates(
    test_students,
    opt = list(course = "HIST 1110"),
    group_cols = c("campus", "college", "subject_course"),
    min_n = 1L
  ) %>%
    dplyr::arrange(campus, college, subject_course) %>%
    dplyr::select(campus, college, subject_course, dfw_pct)

  expect_equal(as.data.frame(modern), as.data.frame(legacy), ignore_attr = TRUE)
})
