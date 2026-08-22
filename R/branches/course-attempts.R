# Shared course-attempt and outcome helpers.
#
# New cones should prefer:
#   get_course_outcome_rates() for DFW/W/D/F/C- metrics
#   get_grade_distribution() for letter-grade distributions
#
# Active grade and DFW analytics should use the course-attempt/outcome APIs in
# this file.


normalize_course_attempt_opt <- function(opt = list()) {
  opt <- opt %||% list()

  if (is.null(opt$course_campus) && !is.null(opt$campus)) opt$course_campus <- opt$campus
  if (is.null(opt$course_college) && !is.null(opt$college)) opt$course_college <- opt$college
  if (is.null(opt$term) && !is.null(opt$terms)) opt$term <- opt$terms
  if (is.null(opt$subj) && !is.null(opt$subject_code)) opt$subj <- opt$subject_code

  opt
}


prepare_course_attempts <- function(students, opt = list()) {
  message("[course-attempts.R] Preparing course attempts from ", nrow(students), " rows")
  opt <- normalize_course_attempt_opt(opt)

  attempts <- filter_class_list(students, opt)

  pop_ids <- opt$population_ids %||% opt$cohort_ids %||% NULL
  if (!is.null(pop_ids) && length(pop_ids) > 0) {
    message("[course-attempts.R] Restricting to supplied student population.")
    attempts <- attempts %>% dplyr::filter(student_id %in% .env$pop_ids)
  }

  if (nrow(attempts) == 0) {
    message("[course-attempts.R] No rows after filtering.")
    return(tibble::tibble())
  }

  # Left edge from config, not a literal. global.R already trims every table to
  # cedar_min_term, so this is a safety net for standalone use — but a hardcoded
  # 201980 silently disagrees with the config the moment the window moves.
  .start <- if (exists("cedar_min_term") && !is.null(cedar_min_term)) cedar_min_term else 201980L
  attempts <- attempts %>% dplyr::filter(term >= .start)

  # The GRADED edge, not the enrollment edge. Every consumer of this function
  # reads final_grade, and a term whose grades have not posted contributes a
  # full denominator with almost no numerator: the newest term read 0.3% DFW
  # against 6-8% elsewhere before this changed. See the right-edge policy in
  # AGENTS.md. Falls back to the config end term when the edge is unavailable
  # (standalone scripts that never ran global.R).
  .end <- if (exists("cedar_graded_through") && !is.null(cedar_graded_through)) {
    cedar_graded_through
  } else if (exists("cedar_report_end_term")) {
    cedar_report_end_term
  } else NULL
  if (!is.null(.end)) {
    message("[course-attempts.R] Excluding terms after the graded edge: ", .end)
    attempts <- attempts %>% dplyr::filter(term <= .end)
  }

  if (nrow(attempts) == 0) {
    message("[course-attempts.R] No rows after term filtering.")
    return(tibble::tibble())
  }

  outcome_status_codes <- c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE)
  attempts <- attempts %>%
    dplyr::filter(registration_status_code %in% outcome_status_codes)

  if (nrow(attempts) == 0) {
    message("[course-attempts.R] No registered/drop rows for outcome analysis.")
    return(tibble::tibble())
  }

  attempts <- attempts %>%
    dplyr::mutate(
      final_grade_raw = dplyr::na_if(trimws(as.character(final_grade)), ""),
      final_grade = dplyr::case_when(
        registration_status_code %in% STATUS_DROP_EARLY ~ "Drop",
        registration_status_code %in% STATUS_DROP_LATE &
          is.na(final_grade_raw) ~ "W",
        TRUE ~ final_grade_raw
      )
    ) %>%
    dplyr::filter(is.na(final_grade) | final_grade != "AUD") %>%
    dplyr::distinct(student_id, campus, college, crn, .keep_all = TRUE)

  if ("points" %in% names(attempts)) attempts$points <- NULL
  attempts <- attempts %>%
    dplyr::left_join(grades_to_points, by = c("final_grade" = "grade"))

  message("[course-attempts.R] Prepared attempts: ", nrow(attempts), " rows")
  attempts
}


summarize_outcome_status_exclusions <- function(students, opt = list()) {
  opt <- normalize_course_attempt_opt(opt)
  expected_codes <- c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE)

  scoped <- filter_class_list(students, opt)

  pop_ids <- opt$population_ids %||% opt$cohort_ids %||% NULL
  if (!is.null(pop_ids) && length(pop_ids) > 0) {
    scoped <- scoped %>% dplyr::filter(student_id %in% .env$pop_ids)
  }

  if (nrow(scoped) == 0) return(tibble::tibble())

  .start2 <- if (exists("cedar_min_term") && !is.null(cedar_min_term)) cedar_min_term else 201980L
  scoped <- scoped %>% dplyr::filter(term >= .start2)

  # Same graded edge as prepare_course_attempts() above — this path also reads
  # final_grade, so it must not reach into an ungraded term.
  .end2 <- if (exists("cedar_graded_through") && !is.null(cedar_graded_through)) {
    cedar_graded_through
  } else if (exists("cedar_report_end_term")) {
    cedar_report_end_term
  } else NULL
  if (!is.null(.end2)) {
    scoped <- scoped %>% dplyr::filter(term <= .end2)
  }

  if (nrow(scoped) == 0) return(tibble::tibble())

  if (!"registration_status" %in% names(scoped)) {
    scoped$registration_status <- NA_character_
  }

  scoped %>%
    dplyr::mutate(
      final_grade_clean = dplyr::na_if(trimws(as.character(final_grade)), ""),
      status_code = dplyr::if_else(
        is.na(registration_status_code) | registration_status_code == "",
        "(missing)",
        as.character(registration_status_code)
      ),
      status_label = dplyr::if_else(
        is.na(registration_status) | registration_status == "",
        "",
        as.character(registration_status)
      )
    ) %>%
    dplyr::filter(is.na(registration_status_code) |
                    !registration_status_code %in% expected_codes) %>%
    dplyr::group_by(campus, college, term, subject_course, status_code, status_label) %>%
    dplyr::summarize(
      rows = dplyr::n(),
      students = dplyr::n_distinct(student_id),
      nonblank_grade_rows = sum(!is.na(final_grade_clean), na.rm = TRUE),
      grade_values = paste(sort(unique(final_grade_clean[!is.na(final_grade_clean)])),
                           collapse = ", "),
      .groups = "drop"
    ) %>%
    dplyr::mutate(grade_values = dplyr::na_if(grade_values, "")) %>%
    dplyr::arrange(dplyr::desc(nonblank_grade_rows), dplyr::desc(rows),
                   term, subject_course, status_code)
}


count_attempt_grades <- function(attempts, group_cols) {
  if (nrow(attempts) == 0) {
    message("[course-attempts.R] count_attempt_grades: empty input.")
    return(data.frame())
  }

  group_cols <- as.character(convert_param_to_list(group_cols))
  missing_cols <- setdiff(group_cols, names(attempts))
  if (length(missing_cols) > 0) {
    stop("[course-attempts.R] Missing grouping columns: ",
         paste(missing_cols, collapse = ", "))
  }

  attempts %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(group_cols, "final_grade")))) %>%
    dplyr::summarize(count = dplyr::n(), .groups = "keep")
}


classify_attempt_outcomes <- function(attempts, policy = "cedar_dfw",
                                      passing_values = passing_grades) {
  if (!policy %in% c("cedar_dfw")) {
    stop("[course-attempts.R] Unsupported outcome policy: ", policy)
  }
  if (nrow(attempts) == 0) return(tibble::tibble())
  passing_values <- as.character(passing_values %||% passing_grades)

  attempts %>%
    dplyr::mutate(
      .grade = final_grade,
      is_blank_outcome = is.na(.grade) | .grade == "",
      is_early_drop = registration_status_code %in% STATUS_DROP_EARLY | .grade == "Drop",
      is_late_withdrawal = !is_early_drop &
        (registration_status_code %in% STATUS_DROP_LATE | .grade == "W"),
      is_pass = !is_early_drop & !is_late_withdrawal &
        !is_blank_outcome & .grade %in% .env$passing_values,
      is_c_minus = !is_early_drop & !is_late_withdrawal &
        .grade %in% c("C-", "RC-"),
      is_d = !is_early_drop & !is_late_withdrawal &
        .grade %in% c("D+", "D", "D-", "RD+", "RD", "RD-"),
      is_f = !is_early_drop & !is_late_withdrawal &
        .grade %in% c("F", "RF"),
      is_other_nonpassing = !is_early_drop & !is_late_withdrawal &
        !is_blank_outcome & !is_pass & !is_c_minus & !is_d & !is_f,
      is_failed_legacy = !is_early_drop & !is_late_withdrawal &
        !is_blank_outcome & !is_pass,
      is_denominator_attempt = is_pass | is_failed_legacy | is_late_withdrawal,
      is_dfw_legacy = is_failed_legacy | is_late_withdrawal,
      is_dfw_strict = is_d | is_f | is_late_withdrawal,
      is_below_c = is_c_minus | is_d | is_f | is_other_nonpassing | is_late_withdrawal,
      outcome_category = dplyr::case_when(
        is_early_drop ~ "early_drop",
        is_late_withdrawal ~ "w_late_withdrawal",
        is_pass ~ "pass",
        is_c_minus ~ "c_minus",
        is_d ~ "d",
        is_f ~ "f",
        is_other_nonpassing ~ "other_nonpassing",
        is_blank_outcome ~ "missing",
        TRUE ~ "other"
      )
    ) %>%
    dplyr::select(-.grade)
}


summarize_attempt_outcomes <- function(classified, group_cols, min_n = 1L) {
  min_n <- suppressWarnings(as.integer(min_n %||% 1L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 1L

  if (nrow(classified) == 0) return(tibble::tibble())

  group_cols <- as.character(convert_param_to_list(group_cols))
  missing_cols <- setdiff(group_cols, names(classified))
  if (length(missing_cols) > 0) {
    stop("[course-attempts.R] Missing grouping columns: ",
         paste(missing_cols, collapse = ", "))
  }

  safe_pct <- function(num, den) {
    dplyr::if_else(den > 0, round(100 * num / den, 2), NA_real_)
  }

  classified %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) %>%
    dplyr::summarize(
      n_attempts = sum(is_denominator_attempt, na.rm = TRUE),
      n_pass = sum(is_pass, na.rm = TRUE),
      n_c_minus = sum(is_c_minus, na.rm = TRUE),
      n_d = sum(is_d, na.rm = TRUE),
      n_f = sum(is_f, na.rm = TRUE),
      n_w = sum(is_late_withdrawal, na.rm = TRUE),
      n_early_drop = sum(is_early_drop, na.rm = TRUE),
      n_other_nonpassing = sum(is_other_nonpassing, na.rm = TRUE),
      n_missing = sum(is_blank_outcome, na.rm = TRUE),
      passed = n_pass,
      failed = sum(is_failed_legacy, na.rm = TRUE),
      early_dropped = n_early_drop,
      late_dropped = n_w,
      n_dfw = failed + late_dropped,
      n_dfw_strict = sum(is_dfw_strict, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      dfw_pct = safe_pct(n_dfw, n_attempts),
      w_pct = safe_pct(n_w, n_attempts),
      df_pct = safe_pct(n_d + n_f, n_attempts),
      below_c_pct = safe_pct(n_c_minus + n_d + n_f + n_w + n_other_nonpassing, n_attempts),
      dfw_strict_pct = safe_pct(n_dfw_strict, n_attempts)
    ) %>%
    dplyr::filter(n_attempts >= min_n)
}


get_course_outcome_rates <- function(students, opt = list(),
                                     group_cols = c("campus", "college", "subject_course"),
                                     min_n = 1L) {
  attempts <- prepare_course_attempts(students, opt)
  classified <- classify_attempt_outcomes(
    attempts,
    passing_values = opt$passing_grades %||% passing_grades
  )
  summarize_attempt_outcomes(classified, group_cols = group_cols, min_n = min_n)
}


get_course_dfw_demographics <- function(students, opt = list(),
                                        group_col = "student_classification",
                                        min_n = 1L,
                                        max_groups = NULL) {
  opt <- normalize_course_attempt_opt(opt)
  group_col <- as.character(group_col)[[1]]
  min_n <- suppressWarnings(as.integer(min_n %||% 1L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 1L

  attempts <- prepare_course_attempts(students, opt)
  if (nrow(attempts) == 0) return(tibble::tibble())

  if (!group_col %in% names(attempts)) {
    stop("[course-attempts.R] Missing demographic grouping column: ", group_col)
  }

  safe_pct <- function(num, den) {
    if (length(den) == 1L) {
      if (is.na(den) || den <= 0) return(rep(NA_real_, length(num)))
      return(round(100 * num / den, 1))
    }
    ifelse(den > 0, round(100 * num / den, 1), NA_real_)
  }

  classified <- classify_attempt_outcomes(
    attempts,
    passing_values = opt$passing_grades %||% passing_grades
  )
  classified$group_col <- group_col
  classified$group <- trimws(as.character(classified[[group_col]]))
  classified$group[is.na(classified$group) | classified$group == ""] <- "(Missing)"

  result <- classified %>%
    dplyr::group_by(group_col, group) %>%
    dplyr::summarize(
      n_attempts = sum(is_denominator_attempt, na.rm = TRUE),
      n_pass = sum(is_pass, na.rm = TRUE),
      n_dfw = sum(is_dfw_legacy, na.rm = TRUE),
      n_late_withdrawal = sum(is_late_withdrawal, na.rm = TRUE),
      n_early_drop = sum(is_early_drop, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::filter(n_attempts >= min_n) %>%
    dplyr::mutate(
      dfw_pct = safe_pct(n_dfw, n_attempts),
      late_withdrawal_pct = safe_pct(n_late_withdrawal, n_attempts),
      early_drop_pct = safe_pct(n_early_drop, n_attempts + n_early_drop),
      share_of_dfw = safe_pct(n_dfw, sum(n_dfw, na.rm = TRUE)),
      share_of_attempts = safe_pct(n_attempts, sum(n_attempts, na.rm = TRUE))
    ) %>%
    dplyr::arrange(dplyr::desc(n_dfw), dplyr::desc(dfw_pct), group)

  if (!is.null(max_groups)) {
    max_groups <- suppressWarnings(as.integer(max_groups))
    if (!is.na(max_groups) && max_groups > 0L) {
      result <- result %>% dplyr::slice_head(n = max_groups)
    }
  }

  result
}


get_course_dfw_context <- function(students, opt = list(), min_cell = 5L) {
  opt <- normalize_course_attempt_opt(opt)
  courses <- opt$course %||% opt$courses
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-attempts.R] opt$course is required for DFW context.")
  }
  courses <- as.character(courses)

  min_cell <- suppressWarnings(as.integer(min_cell %||% 5L))
  if (length(min_cell) == 0 || is.na(min_cell) || min_cell < 1L) min_cell <- 5L

  empty_result <- function(reason = NULL, suppressed = FALSE) {
    list(
      summary = tibble::tibble(),
      detail = tibble::tibble(),
      total_dfw_student_terms = 0L,
      min_cell = min_cell,
      merged_buckets = FALSE,
      suppressed = suppressed,
      suppression_reason = reason
    )
  }

  focal_attempts <- prepare_course_attempts(students, opt)
  if (nrow(focal_attempts) == 0) {
    return(empty_result("No course attempts found for the selected scope."))
  }

  # CAMPUS_ROLLUP: identify the selected focal DFW event once per student-term-
  # course after the caller's campus scope has already been applied.
  classified_focal <- classify_attempt_outcomes(
    focal_attempts,
    passing_values = opt$passing_grades %||% passing_grades
  ) %>%
    dplyr::filter(is_dfw_legacy) %>%
    dplyr::distinct(student_id, term, subject_course, .keep_all = TRUE)

  if (nrow(classified_focal) == 0) {
    return(empty_result("No DFW outcomes found for the selected course scope."))
  }

  focal_student_terms <- classified_focal %>%
    dplyr::distinct(student_id, term)

  context_opt <- opt
  context_opt$course <- NULL
  context_opt$courses <- NULL
  context_opt$crn <- NULL
  context_opt$inst <- NULL
  context_opt$course_campus <- NULL
  context_opt$course_college <- NULL
  context_opt$term <- sort(unique(focal_student_terms$term))
  context_opt$population_ids <- unique(focal_student_terms$student_id)

  context_attempts <- prepare_course_attempts(students, context_opt)
  if (nrow(context_attempts) == 0) {
    return(empty_result("No same-term course attempts found for DFW students."))
  }

  # CAMPUS_ROLLUP: this is the student's institution-wide same-term workload
  # context. Campus is deliberately cleared above so campus moves and mixed-
  # campus schedules do not turn one course into multiple workload attempts.
  context_courses <- classify_attempt_outcomes(
    context_attempts,
    passing_values = opt$passing_grades %||% passing_grades
  ) %>%
    dplyr::semi_join(focal_student_terms, by = c("student_id", "term")) %>%
    dplyr::filter(is_denominator_attempt) %>%
    # CAMPUS_ROLLUP: one institution-wide workload attempt per student-course.
    dplyr::group_by(student_id, term, subject_course) %>%
    dplyr::summarize(
      is_focal_course = any(subject_course %in% .env$courses, na.rm = TRUE),
      is_pass_course = any(is_pass, na.rm = TRUE),
      is_dfw_course = any(is_dfw_legacy, na.rm = TRUE),
      .groups = "drop"
    )

  if (nrow(context_courses) == 0) {
    return(empty_result("No classifiable same-term course attempts found for DFW students."))
  }

  detail <- context_courses %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(
      attempted_courses = dplyr::n(),
      dfw_courses = sum(is_dfw_course, na.rm = TRUE),
      passed_courses = sum(is_pass_course, na.rm = TRUE),
      focal_dfw_courses = sum(is_focal_course & is_dfw_course, na.rm = TRUE),
      other_attempted_courses = sum(!is_focal_course, na.rm = TRUE),
      other_dfw_courses = sum(!is_focal_course & is_dfw_course, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::filter(focal_dfw_courses > 0) %>%
    dplyr::mutate(
      dfw_share = dplyr::if_else(
        attempted_courses > 0,
        dfw_courses / attempted_courses,
        NA_real_
      ),
      bucket_id = dplyr::case_when(
        other_attempted_courses == 0 ~ "only_course",
        other_dfw_courses == 0 ~ "isolated_dfw",
        dfw_share >= 0.5 ~ "most_courses_dfw",
        TRUE ~ "some_broader_difficulty"
      ),
      bucket = dplyr::case_when(
        bucket_id == "only_course" ~ "Only course attempted",
        bucket_id == "isolated_dfw" ~ "DFW only in this course",
        bucket_id == "most_courses_dfw" ~ "DFW/non-pass in most courses",
        TRUE ~ "Some broader difficulty"
      )
    )

  total_dfw_student_terms <- nrow(detail)
  if (total_dfw_student_terms < min_cell) {
    return(list(
      summary = tibble::tibble(),
      detail = detail,
      total_dfw_student_terms = total_dfw_student_terms,
      min_cell = min_cell,
      merged_buckets = FALSE,
      suppressed = TRUE,
      suppression_reason = paste0(
        "DFW context is hidden because fewer than ", min_cell,
        " DFW student-terms are available."
      )
    ))
  }

  bucket_levels <- c(
    "DFW only in this course",
    "Some broader difficulty",
    "DFW/non-pass in most courses",
    "Only course attempted"
  )

  bucket_labels <- c(
    only_course             = "Only course attempted",
    isolated_dfw            = "DFW only in this course",
    some_broader_difficulty = "Some broader difficulty",
    most_courses_dfw        = "DFW/non-pass in most courses"
  )

  # A bucket under min_cell is folded into its nearest neighbour rather than
  # hiding the whole panel. One thin bucket should not cost the other few
  # hundred student-terms their display: an ABQ-only view of a large Gen Ed
  # course routinely puts 2 people in "Only course attempted" while the other
  # three buckets hold hundreds.
  #
  # Merging rather than dropping is also what actually protects the thin bucket.
  # The panel publishes the total, so dropping one row of four leaves its count
  # recoverable by subtraction.
  #
  # The chain runs from "difficulty confined to this course" toward "difficulty
  # across most courses". "Only course attempted" sits at the confined end
  # because there is no second course in which broader difficulty could show up.
  merge_chain <- c("only_course", "isolated_dfw",
                   "some_broader_difficulty", "most_courses_dfw")

  present <- merge_chain[merge_chain %in% detail$bucket_id]
  members <- lapply(present, identity)
  counts <- vapply(present, function(id) sum(detail$bucket_id == id), integer(1))

  repeat {
    if (length(counts) <= 1) break
    thin <- which(counts < min_cell)
    if (length(thin) == 0) break
    i <- thin[[1]]
    # Merge toward the next link in the chain, or back down at the far end.
    j <- if (i < length(counts)) i + 1L else i - 1L
    lo <- min(i, j)
    hi <- max(i, j)
    members[[lo]] <- c(members[[lo]], members[[hi]])
    counts[[lo]] <- counts[[lo]] + counts[[hi]]
    members <- members[-hi]
    counts <- counts[-hi]
  }

  merged_buckets <- length(members) < length(present)

  # Name each group by its parts, listed in the order the legend already uses.
  group_label <- function(ids) {
    labs <- unname(bucket_labels[ids])
    paste(labs[order(match(labs, bucket_levels))], collapse = " + ")
  }
  label_map <- character(0)
  for (ids in members) label_map[ids] <- group_label(ids)

  display_levels <- vapply(members, group_label, character(1))[
    order(vapply(
      members,
      function(ids) min(match(unname(bucket_labels[ids]), bucket_levels)),
      numeric(1)
    ))
  ]

  detail <- detail %>%
    dplyr::mutate(bucket = unname(label_map[bucket_id]))

  summary <- detail %>%
    dplyr::mutate(bucket = factor(bucket, levels = display_levels)) %>%
    dplyr::group_by(bucket) %>%
    dplyr::summarize(
      n_student_terms = dplyr::n(),
      pct_student_terms = round(100 * n_student_terms / total_dfw_student_terms, 1),
      median_attempted_courses = stats::median(attempted_courses, na.rm = TRUE),
      median_dfw_courses = stats::median(dfw_courses, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(bucket)

  # Reachable only when everything has collapsed into one group that is still
  # under min_cell, which means the total is too. The guard above normally
  # catches that first; this is the backstop.
  if (any(summary$n_student_terms < min_cell)) {
    return(list(
      summary = tibble::tibble(),
      detail = detail,
      total_dfw_student_terms = total_dfw_student_terms,
      min_cell = min_cell,
      merged_buckets = FALSE,
      suppressed = TRUE,
      suppression_reason = paste0(
        "DFW context is hidden because fewer than ", min_cell,
        " DFW student-terms are available."
      )
    ))
  }

  list(
    summary = summary,
    detail = detail,
    total_dfw_student_terms = total_dfw_student_terms,
    min_cell = min_cell,
    merged_buckets = merged_buckets,
    suppressed = FALSE,
    suppression_reason = NULL
  )
}


get_grade_distribution <- function(students, opt = list(), group_cols,
                                   min_n = 1L) {
  min_n <- suppressWarnings(as.integer(min_n %||% 1L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 1L

  attempts <- prepare_course_attempts(students, opt)
  if (nrow(attempts) == 0) return(tibble::tibble())

  group_cols <- as.character(convert_param_to_list(group_cols))
  missing_cols <- setdiff(group_cols, names(attempts))
  if (length(missing_cols) > 0) {
    stop("[course-attempts.R] Missing grouping columns: ",
         paste(missing_cols, collapse = ", "))
  }

  grade_levels <- c("A", "B", "C", "D", "F", "W", "Other")

  dist <- attempts %>%
    classify_attempt_outcomes() %>%
    dplyr::filter(is_denominator_attempt) %>%
    dplyr::mutate(grade_group = dplyr::case_when(
      final_grade %in% c("A", "A+", "A-", "RA", "RA+", "RA-") ~ "A",
      final_grade %in% c("B", "B+", "B-", "RB", "RB+", "RB-") ~ "B",
      final_grade %in% c("C", "C+", "C-", "CR", "RC", "RC+", "RC-", "RCR") ~ "C",
      final_grade %in% c("D", "D+", "D-", "RD", "RD+", "RD-") ~ "D",
      final_grade %in% c("F", "RF") ~ "F",
      is_late_withdrawal ~ "W",
      TRUE ~ "Other"
    )) %>%
    dplyr::count(dplyr::across(dplyr::all_of(c(group_cols, "grade_group")))) %>%
    tidyr::pivot_wider(names_from = grade_group, values_from = n, values_fill = 0)

  for (lvl in grade_levels) {
    if (!lvl %in% names(dist)) dist[[lvl]] <- 0L
  }

  dist$total <- rowSums(dist[, grade_levels, drop = FALSE], na.rm = TRUE)

  for (lvl in grade_levels) {
    dist[[paste0(lvl, "_pct")]] <- dplyr::if_else(
      dist$total > 0,
      round(100 * dist[[lvl]] / dist$total, 1),
      NA_real_
    )
  }

  dist %>%
    dplyr::filter(total >= min_n) %>%
    dplyr::select(dplyr::all_of(group_cols), dplyr::all_of(grade_levels),
                  total, dplyr::all_of(paste0(grade_levels, "_pct")))
}
