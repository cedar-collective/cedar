context("Course Attempts and Outcome APIs")

test_that("AUD is excluded across classifiers without erasing genuine withdrawals", {
  students <- test_students_audits
  audit_ids <- students$student_id[trimws(students$final_grade) %in% GRADES_EXCLUDED_FROM_OUTCOMES]
  expected_ids <- c("EC09-DG-NA", "EC09-DW-BLANK", "EC09-DW-A", "EC09-RE-A", "EC09-RE-F")

  canonical <- classify_enrollment_outcomes(students)
  expect_setequal(canonical$student_id, expected_ids)
  expect_equal(sum(canonical$outcome == "dfw"), 4L)
  expect_false(any(canonical$student_id %in% audit_ids))
  expect_setequal(classify_outcomes(students)$student_id, expected_ids)

  grade_only <- classify_grades(students)
  expect_true(all(grade_only$grade_outcome[grade_only$student_id %in% audit_ids] == "unknown"))

  direct <- classify_attempt_outcomes(students)
  expect_setequal(direct$student_id[which(direct$is_denominator_attempt)], expected_ids)
  expect_false(any(direct$is_dfw_legacy[direct$student_id %in% audit_ids]))

  edges <- data_objects$cedar_edges
  attempts <- keyed_attempts(students)
  prepared <- prepare_course_attempts(attempts, list(course = "HIST 1110", data_edges = edges))
  classified <- attempt_outcome_flags(prepared)
  expect_setequal(classified$student_id[which(classified$is_denominator_attempt)], expected_ids)
  rate <- get_course_outcome_rates(attempts, list(course = "HIST 1110", data_edges = edges))
  expect_equal(rate$n_attempts, 5L)
  expect_equal(rate$n_dfw, 4L)
  expect_equal(rate$n_pass, 1L)
  expect_equal(rate$n_w, 3L)
  expect_equal(rate$dfw_pct, 80)
  expect_equal(rate$n_early_drop, 3L) # audit registration churn is still counted separately
})


test_that("recycled CRNs preserve later attempts while same-term duplicates collapse", {
  attempts <- prepare_course_attempts(keyed_attempts(test_students_reused_crn), list(subj = "HIST"))

  expect_equal(nrow(attempts), 4L)
  repeated <- attempts %>% filter(student_id == "EC08-A", subject_course == "HIST 1110")
  expect_equal(repeated$term, c(202010L, 202080L))
  expect_equal(repeated$final_grade, c("A", "F"))
  expect_equal(sum(attempts$student_id == "EC08-A" & attempts$term == 202080L), 1L)
  expect_equal(attempts$final_grade[attempts$subject_course == "HIST 1120"], "W")
})


test_that("course outcomes reconcile across term partitions and wider course scope", {
  attempts <- keyed_attempts(test_students_reused_crn)
  opt <- list(course = "HIST 1110", course_campus = "ABQ",
              data_edges = data_objects$cedar_edges)
  pooled <- get_course_outcome_rates(attempts, opt)
  expect_equal(pooled$n_attempts, 3L)
  expect_equal(pooled$n_pass, 2L)
  expect_equal(pooled$n_dfw, 1L)
  expect_equal(pooled$dfw_pct, 33.33)

  # Separate term queries must sum to the multi-term query; grouping a single
  # already-deduplicated frame by term would not expose the missing-term bug.
  separate_terms <- bind_rows(lapply(c(202010L, 202080L), function(term) {
    term_opt <- opt
    term_opt$term <- term
    get_course_outcome_rates(attempts, term_opt)
  }))
  expect_equal(sum(separate_terms$n_attempts), pooled$n_attempts)
  expect_equal(sum(separate_terms$n_dfw), pooled$n_dfw)

  wider <- get_course_outcome_rates(attempts, list(subj = "HIST"))
  expect_equal(filter(wider, subject_course == "HIST 1110"), pooled)
  expect_equal(wider$n_attempts[wider$subject_course == "HIST 1120"], 1L)
  expect_equal(wider$n_dfw[wider$subject_course == "HIST 1120"], 1L)

  grades <- get_grade_distribution(attempts, opt, group_cols = "subject_course")
  expect_equal(grades$total, pooled$n_attempts)
  expect_equal(grades$A, 2L)
  expect_equal(grades$F, 1L)
})


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
  # The two classifiers agree on every kind of grade: cedar_attempts derives
  # its outcome from these flags and must match classify_enrollment_outcomes().
  expect_equal(classify_enrollment_outcomes(attempts)$outcome,
               ifelse(standard$is_pass, "pass", "dfw")[standard$is_denominator_attempt])

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


# What the class list goes through before a reader sees an attempt: the
# transform's dedup, then build_attempts() (keyed_attempts(), setup.R). The
# hub reads the result and decides nothing again.
test_that("the attempt table normalizes drops, excludes audits, and deduplicates", {
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

  result <- prepare_course_attempts(
    keyed_attempts(designed), opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges)
  )

  expect_false("attempt-aud" %in% result$student_id)
  expect_false("attempt-wl" %in% result$student_id)
  expect_equal(result$final_grade[result$student_id == "attempt-dr"], "Drop")
  expect_equal(result$final_grade[result$student_id == "attempt-dd"], "Drop")
  expect_equal(result$final_grade[result$student_id == "attempt-dw"], "W")
  expect_true(is.na(result$final_grade[result$student_id == "attempt-blank"]))
  expect_equal(sum(result$student_id == "attempt-dup"), 1L)
  expect_equal(names(result), ATTEMPTS_COLUMNS)
  # The scope is the table's own: a different claimed edge is refused, an
  # option the table cannot answer is refused, and a class list is not a table.
  expect_error(
    prepare_course_attempts(keyed_attempts(designed),
                            list(course = "HIST 1110",
                                 data_edges = modifyList(data_objects$cedar_edges,
                                                         list(last_graded = 201980L)))),
    "was built to")
  expect_error(prepare_course_attempts(keyed_attempts(designed), list(classification = "Freshman")),
               "does not carry")
  expect_error(prepare_course_attempts(designed, list(course = "HIST 1110")), "build_attempts")
})


# The hub counts attempt_outcome_flags(), read off the stored category; they
# must be the classifier's flags over the same rows, under the default policy
# and under the page's C-/D opt-in, and under the default `is_pass` is the
# stored `pass` category itself.
test_that("attempt_outcome_flags reproduces the classifier from the stored category", {
  attempts <- test_attempts
  flag_cols <- grep("^is_", names(classify_attempt_outcomes(attempts[1, ])), value = TRUE)
  for (passing in list(GRADES_PASS, GRADES_PASS_SUB_C_OPT_IN)) {
    from_table <- attempt_outcome_flags(attempts, passing_values = passing)
    reclassified <- classify_attempt_outcomes(attempts, passing_values = passing)
    expect_equal(as.data.frame(from_table[flag_cols]), as.data.frame(reclassified[flag_cols]))
  }
  default <- attempt_outcome_flags(attempts)
  expect_equal(default$is_pass, attempts$outcome_category == "pass")
  expect_equal(default$is_dfw_legacy, attempts$outcome %in% "dfw")
  expect_gt(sum(default$is_pass), 0L)
  expect_gt(sum(attempt_outcome_flags(attempts, GRADES_PASS_SUB_C_OPT_IN)$is_pass), sum(default$is_pass))

  odd <- attempts[1, ]; odd$outcome_category <- "other"
  expect_error(attempt_outcome_flags(odd), "never writes")
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

  result <- summarize_outcome_status_exclusions(
    designed, opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges)
  )

  expect_setequal(result$status_code, c("WL", "ZZ"))
  expect_equal(result$nonblank_grade_rows[result$status_code == "WL"], 0L)
  expect_equal(result$nonblank_grade_rows[result$status_code == "ZZ"], 1L)
  expect_equal(result$grade_values[result$status_code == "ZZ"], "B")
})


test_that("get_course_outcome_rates exposes nuanced DFW components", {
  result <- get_course_outcome_rates(
    test_attempts,
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
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


# The groups are the student-term table's, never the class list's (ADR-001
# step 5): the loaded class list carries no description, so each designed seat
# gets its classification and primary major from a student-term row built here.
dfw_demo_rows <- function(ids, statuses, grades) {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)
  dplyr::bind_rows(lapply(seq_along(ids), function(i) {
    base_row %>% dplyr::mutate(
      student_id = ids[[i]], crn = as.character(93000 + i),
      registration_status_code = statuses[[i]], final_grade = grades[[i]]
    )
  }))
}
dfw_demo_terms <- function(rows, classification, major, pre_major = FALSE) {
  tibble::tibble(
    student_id = rows$student_id, term = as.integer(rows$term),
    student_classification = classification,
    primary_major_code = major, is_pre_major = pre_major
  )
}

test_that("get_course_dfw_demographics summarizes rate and composition", {
  designed <- dfw_demo_rows(
    paste0("demo-0", 1:6),
    c("RE", "RE", "DW", "DR", "RE", "RE"),
    c("A", "F", NA, NA, "C-", "A")
  )
  # Two codes programs.csv does not carry, so each is named as itself; the
  # second is a pre-major, so it reads with the suffix every major table uses.
  st <- dfw_demo_terms(
    designed,
    classification = c(rep("Freshman", 4), "Sophomore", "Sophomore"),
    major = c(rep("ZZHIST", 4), "ZZBIOL", "ZZBIOL"),
    pre_major = c(rep(FALSE, 4), TRUE, TRUE)
  )

  attempts <- keyed_attempts(designed)
  result <- get_course_dfw_demographics(
    attempts, st,
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
    group_col = "major_code", dims = test_dims
  )

  history <- result %>% dplyr::filter(group == "ZZHIST")
  biology <- result %>% dplyr::filter(group == "ZZBIOL (pre-major)")

  expect_equal(history$n_attempts, 3L)
  expect_equal(history$n_dfw, 2L)
  expect_equal(history$n_early_drop, 1L)
  expect_equal(history$dfw_pct, 66.7)
  expect_equal(history$share_of_dfw, 66.7)
  expect_equal(biology$n_attempts, 2L)
  expect_equal(biology$n_dfw, 1L)

  by_class <- get_course_dfw_demographics(
    attempts, st,
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
    group_col = "student_classification"
  )
  expect_equal(sort(by_class$group), c("Freshman", "Sophomore"))
  expect_equal(by_class$n_dfw[by_class$group == "Freshman"], 2L)

  # A seat with no student-term row is refused, never grouped as missing.
  expect_error(
    get_course_dfw_demographics(
      attempts, st[-1, ],
      opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges)
    ),
    "no row on cedar_student_terms"
  )
  # Grouping by major needs the mapping files that name each program.
  expect_error(
    get_course_dfw_demographics(
      attempts, st,
      opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
      group_col = "major_code"
    ),
    "pass dims"
  )
})


test_that("get_course_dfw_demographics honors caller-supplied passing grades", {
  designed <- dfw_demo_rows(c("threshold-01", "threshold-02"), c("RE", "RE"), c("C-", "A"))
  st <- dfw_demo_terms(designed, classification = "Sophomore", major = "ZZBIOL")

  result <- get_course_dfw_demographics(
    keyed_attempts(designed), st,
    opt = list(
      course = "HIST 1110",
      passing_grades = GRADES_PASS_SUB_C_OPT_IN,
      data_edges = data_objects$cedar_edges
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
    keyed_attempts(designed),
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
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
    keyed_attempts(designed),
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
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
    keyed_attempts(dplyr::bind_rows(focal_only, paired)),
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
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
    test_attempts,
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
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
    test_attempts,
    opt = list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
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


# cedar_attempts (R/branches/attempts.R): the class list classified once, to
# the graded edge. Its stored outcome must be what the hub counts over it
# (count_attempt_outcomes() against get_course_outcome_rates(), course by
# course) and the canonical classifier's, row by row: a reader moving to the
# table must see no number change. HIST 1110 in test_students is the course
# pinned above (36 attempts: 23 pass, 4 fail, 9 late withdrawals).
test_that("cedar_attempts reproduces the per-request outcome rates for every course", {
  edges <- data_objects$cedar_edges
  attempts <- attempts_for(test_students)
  expect_equal(names(attempts), ATTEMPTS_COLUMNS)
  expect_true(all(attempts$term <= edges$last_graded))

  hist <- attempts %>% filter(subject_course == "HIST 1110")
  expect_equal(sum(!is.na(hist$outcome)), 36L)
  expect_equal(sum(hist$outcome %in% "pass"), 23L)
  expect_equal(sum(hist$outcome %in% "dfw"), 13L)
  expect_equal(sum(hist$outcome_category == "w_late_withdrawal"), 9L)

  # Every course and term, against the hub's path over the same table.
  per_request <- get_course_outcome_rates(
    attempts, list(term = sort(unique(test_students$term)), data_edges = edges),
    group_cols = c("campus", "college", "term", "subject_course")) %>%
    select(campus, college, term, subject_course, n_attempts, n_pass, n_dfw, n_w) %>%
    filter(n_attempts > 0) %>%
    arrange(campus, college, term, subject_course)
  from_table <- count_attempt_outcomes(attempts) %>%
    group_by(campus, college, term, subject_course) %>%
    summarize(n_attempts = sum(attempts), n_pass = sum(passed), n_dfw = sum(dfw),
              n_w = sum(withdrawn), .groups = "drop") %>%
    filter(n_attempts > 0) %>%
    arrange(campus, college, term, subject_course)
  expect_gt(nrow(per_request), 10L)
  expect_equal(as.data.frame(from_table), as.data.frame(per_request), ignore_attr = TRUE)

  # Row by row, outcome is classify_enrollment_outcomes()'s; an early drop and
  # a registered row with no grade carry none.
  canonical <- classify_enrollment_outcomes(filter(test_students, term <= edges$last_graded)) %>%
    select(student_id, term, campus, subject_course, canonical = outcome)
  joined <- attempts %>% filter(!is.na(outcome)) %>%
    full_join(canonical, by = c("student_id", "term", "campus", "subject_course"))
  expect_equal(joined$outcome, joined$canonical)
  expect_true(all(is.na(attempts$outcome[attempts$outcome_category %in% c("early_drop", "missing")])))
  expect_true(all(attempts$final_grade[attempts$outcome_category == "early_drop"] == "Drop"))
})


test_that("cedar_attempts maps every kind of grade to the default policy", {
  # The shared fixture holds no I, NC, NR, P, S or unfamiliar grade inside the
  # graded edge, so the mapping is checked on graded class-list rows given each
  # grade in turn: one registered row per grade, plus a late drop with no grade.
  edges <- data_objects$cedar_edges
  grades <- c("A+", "C", "CR", "C-", "D+", "D", "D-", "F", "W", "I",
              "NC", "NR", "P", "S", "UNSEEN_CODE", "AUD", "")
  rows <- test_students %>%
    dplyr::filter(as.integer(term) <= edges$last_graded,
                  registration_status_code %in% STATUS_REGISTERED) %>%
    dplyr::slice_head(n = length(grades) + 1L)
  rows$final_grade <- c(grades, NA_character_)
  rows$registration_status_code[length(grades) + 1L] <- "DW"
  attempts <- build_attempts(rows, edges)

  by_grade <- setNames(attempts$outcome, attempts$final_grade)
  expect_equal(unname(by_grade[c("A+", "C", "CR")]), rep("pass", 3))
  dfw <- c("C-", "D+", "D", "D-", "F", "W", "I", "NC", "NR", "P", "S", "UNSEEN_CODE")
  expect_equal(unname(by_grade[dfw]), rep("dfw", length(dfw)))
  # The audit is not an attempt; the blank registered grade is unknown.
  expect_false("AUD" %in% attempts$final_grade)
  expect_equal(sum(is.na(attempts$outcome)), 1L)
  # The late drop with no grade is a withdrawal, and DFW.
  expect_equal(sum(attempts$outcome_category == "w_late_withdrawal"), 2L)
  expect_equal(sum(attempts$outcome %in% "dfw"), length(dfw) + 1L)
})


test_that("cedar_attempts is refused when built to another edge, build or set of codes", {
  edges <- data_objects$cedar_edges
  attempts <- attempts_for(test_students)
  expect_true(attempts_is_current(attempts, test_students, edges))
  expect_false(attempts_is_current(attempts, test_students,
                                   modifyList(edges, list(last_graded = 202080L))))
  older <- attempts; attr(older, "attempts_build_version") <- ATTEMPTS_BUILD_VERSION - 1L
  expect_false(attempts_is_current(older, test_students, edges))
  expect_false(attempts_is_current(NULL, test_students, edges))
  rn <- rn01_course_tables()
  expect_false(attempts_is_current(attempts, rn$cedar_registrations, edges))
  expect_error(require_current_attempts(attempts, rn$cedar_registrations, "a reader"), "build_attempts")
  expect_error(build_attempts(test_students, modifyList(edges, list(last_graded = NULL))),
               "graded edge")
  expect_error(build_attempts(bind_rows(test_students, test_students[1, ]), edges),
               "more than one class-list row")
})


# cedar_course_terms carries the attempts' outcome counts per course-term-
# part-of-term: they sum to the table's, and a term past the graded edge has
# NA, not zero. Built to an edge of Fall 2020, so Spring 2021 is ungraded.
test_that("cedar_course_terms carries outcome counts, unknown past the graded edge", {
  edges <- modifyList(data_objects$cedar_edges, list(last_graded = 202080L))
  attempts <- attempts_for(test_students, edges)
  course_terms <- build_course_terms(test_students, attempts, test_sections)
  expect_equal(names(course_terms), COURSE_TERMS_COLUMNS)
  expect_identical(attr(course_terms, "graded_edge"), 202080L)

  # The outcome counts are the class list's side: a graded course-term the
  # schedule alone offers (no class-list row) has unknown outcomes, not zero.
  graded <- course_terms %>% filter(term <= 202080L, !is.na(registered))
  offered_only <- course_terms %>% filter(term <= 202080L, is.na(registered))
  ungraded <- course_terms %>% filter(term > 202080L)
  expect_gt(nrow(ungraded), 0L)
  expect_gt(nrow(offered_only), 0L)
  for (col in c("attempts", "passed", "dfw", "withdrawn")) {
    expect_true(all(is.na(ungraded[[col]])), info = col)
    expect_true(all(is.na(offered_only[[col]])), info = col)
    expect_false(anyNA(graded[[col]]), info = col)
  }
  expect_equal(sum(graded$attempts), sum(!is.na(attempts$outcome)))
  expect_equal(sum(graded$dfw), sum(attempts$outcome %in% "dfw"))
  expect_equal(sum(graded$passed) + sum(graded$dfw), sum(graded$attempts))
  expect_true(all(graded$withdrawn <= graded$dfw))

  expect_true(course_terms_is_current(course_terms, test_students, graded_edge = 202080L))
  expect_false(course_terms_is_current(course_terms, test_students,
                                       graded_edge = data_objects$cedar_edges$last_graded))
  # Attempts from another class list: their course-terms are not this one's.
  expect_error(build_course_terms(test_students, attempts_for(test_students_regstats), test_sections),
               "must come from one class list")
})
