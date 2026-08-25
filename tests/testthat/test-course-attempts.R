context("Course Attempts and Outcome APIs")


test_that("canonical DFW policy is exhaustive and the sub-C exception is narrow", {
  grades <- c(
    "A+", "C", "CR", "C-", "D+", "D", "D-", "F", "W", "I",
    "NC", "NR", "P", "S", "UNSEEN_CODE", "AUD", ""
  )
  attempts <- tibble::tibble(
    student_id = paste0("policy-", seq_along(grades)),
    registration_status_code = "RE",
    final_grade = grades
  )

  standard <- classify_attempt_outcomes(attempts)
  expect_equal(standard$is_pass, c(
    TRUE, TRUE, TRUE, rep(FALSE, length(grades) - 3L)
  ))
  expect_true(all(standard$is_dfw_legacy[4:15]))
  expect_false(any(standard$is_denominator_attempt[16:17]))

  sub_c <- classify_attempt_outcomes(
    attempts,
    passing_values = GRADES_PASS_SUB_C_OPT_IN
  )
  expect_true(all(sub_c$is_pass[4:7]))
  expect_true(all(sub_c$is_dfw_legacy[8:15]))
  expect_true(all(sub_c$is_dfw_legacy[grades %in% c("P", "S")]))

  status_rows <- tibble::tibble(
    student_id = c("early", "late"),
    registration_status_code = c("DR", "DW"),
    final_grade = c(NA_character_, NA_character_)
  )
  classified_status <- classify_enrollment_outcomes(status_rows)
  expect_false("early" %in% classified_status$student_id)
  expect_equal(classified_status$outcome[classified_status$student_id == "late"], "dfw")
})


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
      student_id = "attempt-wl", crn = "91005",
      registration_status_code = "WL", final_grade = NA_character_
    ),
    base_row %>% dplyr::mutate(
      student_id = "attempt-dd", crn = "91006",
      registration_status_code = "DD", final_grade = NA_character_
    ),
    base_row %>% dplyr::mutate(
      student_id = "attempt-blank", crn = "91007",
      registration_status_code = "RE", final_grade = ""
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
  expect_false("attempt-wl" %in% result$student_id)
  expect_equal(result$final_grade[result$student_id == "attempt-dr"], "Drop")
  expect_equal(result$final_grade[result$student_id == "attempt-dd"], "Drop")
  expect_equal(result$final_grade[result$student_id == "attempt-dw"], "W")
  expect_true(is.na(result$final_grade[result$student_id == "attempt-blank"]))
  expect_equal(sum(result$student_id == "attempt-dup"), 1L)
  expect_true("final_grade_raw" %in% names(result))
})


test_that("summarize_outcome_status_exclusions reports excluded status rows and grade signals", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  designed <- dplyr::bind_rows(
    base_row %>% dplyr::mutate(
      student_id = "status-re", crn = "92001",
      registration_status_code = "RE", registration_status = "Student Registered",
      final_grade = "A"
    ),
    base_row %>% dplyr::mutate(
      student_id = "status-wl", crn = "92002",
      registration_status_code = "WL", registration_status = "Wait Listed",
      final_grade = NA_character_
    ),
    base_row %>% dplyr::mutate(
      student_id = "status-zz", crn = "92003",
      registration_status_code = "ZZ", registration_status = "Unexpected",
      final_grade = "B"
    )
  )

  result <- summarize_outcome_status_exclusions(designed, opt = list(course = "HIST 1110"))

  expect_setequal(result$status_code, c("WL", "ZZ"))
  expect_equal(result$nonblank_grade_rows[result$status_code == "WL"], 0L)
  expect_equal(result$nonblank_grade_rows[result$status_code == "ZZ"], 1L)
  expect_equal(result$grade_values[result$status_code == "ZZ"], "B")
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


test_that("get_course_dfw_demographics summarizes rate and composition", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  designed <- dplyr::bind_rows(
    base_row %>% dplyr::mutate(
      student_id = "demo-01", crn = "93001",
      registration_status_code = "RE", final_grade = "A",
      student_classification = "Freshman", major_name = "History"
    ),
    base_row %>% dplyr::mutate(
      student_id = "demo-02", crn = "93002",
      registration_status_code = "RE", final_grade = "F",
      student_classification = "Freshman", major_name = "History"
    ),
    base_row %>% dplyr::mutate(
      student_id = "demo-03", crn = "93003",
      registration_status_code = "DW", final_grade = NA_character_,
      student_classification = "Freshman", major_name = "History"
    ),
    base_row %>% dplyr::mutate(
      student_id = "demo-04", crn = "93004",
      registration_status_code = "DR", final_grade = NA_character_,
      student_classification = "Freshman", major_name = "History"
    ),
    base_row %>% dplyr::mutate(
      student_id = "demo-05", crn = "93005",
      registration_status_code = "RE", final_grade = "C-",
      student_classification = "Sophomore", major_name = "Biology"
    ),
    base_row %>% dplyr::mutate(
      student_id = "demo-06", crn = "93006",
      registration_status_code = "RE", final_grade = "A",
      student_classification = "Sophomore", major_name = "Biology"
    )
  )

  result <- get_course_dfw_demographics(
    designed,
    opt = list(course = "HIST 1110"),
    group_col = "major_name"
  )

  history <- result %>% dplyr::filter(group == "History")
  biology <- result %>% dplyr::filter(group == "Biology")

  expect_equal(history$n_attempts, 3L)
  expect_equal(history$n_dfw, 2L)
  expect_equal(history$n_early_drop, 1L)
  expect_equal(history$dfw_pct, 66.7)
  expect_equal(history$share_of_dfw, 66.7)
  expect_equal(biology$n_attempts, 2L)
  expect_equal(biology$n_dfw, 1L)
})


test_that("get_course_dfw_demographics honors caller-supplied passing grades", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  designed <- dplyr::bind_rows(
    base_row %>% dplyr::mutate(
      student_id = "threshold-01", crn = "94001",
      registration_status_code = "RE", final_grade = "C-",
      student_classification = "Sophomore", major_name = "Biology"
    ),
    base_row %>% dplyr::mutate(
      student_id = "threshold-02", crn = "94002",
      registration_status_code = "RE", final_grade = "A",
      student_classification = "Sophomore", major_name = "Biology"
    )
  )

  result <- get_course_dfw_demographics(
    designed,
    opt = list(
      course = "HIST 1110",
      passing_grades = GRADES_PASS_SUB_C_OPT_IN
    ),
    group_col = "student_classification"
  )

  expect_equal(result$n_attempts, 2L)
  expect_equal(result$n_dfw, 0L)
  expect_equal(result$dfw_pct, 0)
})


test_that("get_course_dfw_context summarizes same-term DFW uniqueness", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  make_row <- function(.student_id, .subject_course, .grade, .crn, .status = "RE") {
    base_row %>%
      dplyr::mutate(
        student_id = .student_id,
        enrollment_id = paste(.student_id, .subject_course, .crn, sep = "-"),
        subject_course = .subject_course,
        subject_code = sub(" .*", "", .subject_course),
        crn = .crn,
        registration_status_code = .status,
        final_grade = .grade
      )
  }

  designed <- dplyr::bind_rows(
    make_row("ctx-isolated", "HIST 1110", "F", "95001"),
    make_row("ctx-isolated", "ENGL 1110", "A", "95002"),
    make_row("ctx-isolated", "MATH 1215", "B", "95003"),

    make_row("ctx-only", "HIST 1110", "F", "95004"),

    make_row("ctx-most", "HIST 1110", "F", "95005"),
    make_row("ctx-most", "ENGL 1110", "F", "95006"),
    make_row("ctx-most", "MATH 1215", "B", "95007"),

    make_row("ctx-some", "HIST 1110", "F", "95008"),
    make_row("ctx-some", "ENGL 1110", "F", "95009"),
    make_row("ctx-some", "MATH 1215", "A", "95010"),
    make_row("ctx-some", "BIOL 1110", "B", "95011"),
    make_row("ctx-some", "CHEM 1110", "C", "95012"),

    make_row("ctx-pass-focal", "HIST 1110", "A", "95013"),
    make_row("ctx-pass-focal", "MATH 1215", "F", "95014")
  )

  result <- get_course_dfw_context(
    designed,
    opt = list(course = "HIST 1110"),
    min_cell = 1L
  )

  expect_false(result$suppressed)
  expect_equal(result$total_dfw_student_terms, 4L)
  expect_setequal(as.character(result$summary$bucket), c(
    "DFW only in this course",
    "Only course attempted",
    "Some broader difficulty",
    "DFW/non-pass in most courses"
  ))
  expect_equal(
    result$summary$n_student_terms[result$summary$bucket == "DFW only in this course"],
    1L
  )
  expect_equal(
    result$summary$n_student_terms[result$summary$bucket == "Only course attempted"],
    1L
  )
  expect_equal(
    result$detail$bucket[result$detail$student_id == "ctx-pass-focal"],
    character(0)
  )
})


test_that("get_course_dfw_context suppresses small context displays", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  designed <- dplyr::bind_rows(
    base_row %>% dplyr::mutate(
      student_id = "ctx-small-1", crn = "96001",
      registration_status_code = "RE", final_grade = "F"
    ),
    base_row %>% dplyr::mutate(
      student_id = "ctx-small-2", crn = "96002",
      registration_status_code = "RE", final_grade = "F"
    )
  )

  result <- get_course_dfw_context(
    designed,
    opt = list(course = "HIST 1110"),
    min_cell = 5L
  )

  expect_true(result$suppressed)
  expect_equal(result$total_dfw_student_terms, 2L)
  expect_equal(nrow(result$summary), 0L)
  expect_match(result$suppression_reason, "fewer than 5")
})


test_that("get_course_dfw_context merges thin buckets instead of hiding the panel", {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)

  # One student per term whose only attempt is the focal course lands in
  # "Only course attempted"; everyone else also fails a second course, so they
  # land in "DFW/non-pass in most courses". The thin bucket must not take the
  # populated one down with it.
  focal_only <- purrr::map_dfr(1:2, function(i) {
    base_row %>% dplyr::mutate(
      student_id = paste0("ctx-merge-solo-", i), crn = paste0("970", i),
      registration_status_code = "RE", final_grade = "F"
    )
  })

  paired <- purrr::map_dfr(1:8, function(i) {
    dplyr::bind_rows(
      base_row %>% dplyr::mutate(
        student_id = paste0("ctx-merge-pair-", i), crn = paste0("971", i),
        registration_status_code = "RE", final_grade = "F"
      ),
      base_row %>% dplyr::mutate(
        student_id = paste0("ctx-merge-pair-", i), crn = paste0("972", i),
        subject_course = "MATH 1220", subject = "MATH", course_number = "1220",
        registration_status_code = "RE", final_grade = "F"
      )
    )
  })

  result <- get_course_dfw_context(
    dplyr::bind_rows(focal_only, paired),
    opt = list(course = "HIST 1110"),
    min_cell = 5L
  )

  expect_false(result$suppressed)
  expect_true(result$merged_buckets)
  expect_equal(result$total_dfw_student_terms, 10L)
  # Nothing is discarded: the merged rows still account for every student-term.
  expect_equal(sum(result$summary$n_student_terms), 10L)
  # And no published cell sits under the threshold.
  expect_true(all(result$summary$n_student_terms >= 5L))
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


test_that("get_course_outcome_rates computes expected course averages", {
  modern <- get_course_outcome_rates(
    test_students,
    opt = list(course = "HIST 1110"),
    group_cols = c("campus", "college", "subject_course"),
    min_n = 1L
  ) %>%
    dplyr::arrange(campus, college, subject_course) %>%
    dplyr::select(campus, college, subject_course, n_attempts, n_pass, failed, late_dropped, dfw_pct)

  expect_equal(nrow(modern), 1L)
  expect_equal(modern$n_attempts, 36L)
  expect_equal(modern$n_pass, 23L)
  expect_equal(modern$failed, 4L)
  expect_equal(modern$late_dropped, 9L)
  expect_equal(modern$dfw_pct, 36.11)
})
