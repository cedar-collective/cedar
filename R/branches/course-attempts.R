# Shared course-attempt and outcome helpers.
#
# New cones should prefer:
#   get_course_outcome_rates() for DFW/W/D/F/C- metrics
#   get_grade_distribution() for letter-grade distributions
#
# get_grades() in gradebook.R remains a legacy/report compatibility facade.


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

  attempts <- attempts %>% dplyr::filter(term >= 201980)

  if (exists("cedar_report_end_term") && !is.null(cedar_report_end_term)) {
    message("[course-attempts.R] Excluding terms after cedar_report_end_term: ",
            cedar_report_end_term)
    attempts <- attempts %>% dplyr::filter(term <= cedar_report_end_term)
  }

  if (nrow(attempts) == 0) {
    message("[course-attempts.R] No rows after term filtering.")
    return(tibble::tibble())
  }

  attempts <- attempts %>%
    dplyr::mutate(
      final_grade_raw = final_grade,
      final_grade = dplyr::case_when(
        registration_status_code %in% STATUS_DROP_EARLY ~ "Drop",
        registration_status_code %in% STATUS_DROP_LATE &
          (is.na(final_grade_raw) | final_grade_raw == "") ~ "W",
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


classify_attempt_outcomes <- function(attempts, policy = "legacy_gradebook") {
  if (!policy %in% c("legacy_gradebook")) {
    stop("[course-attempts.R] Unsupported outcome policy: ", policy)
  }
  if (nrow(attempts) == 0) return(tibble::tibble())

  attempts %>%
    dplyr::mutate(
      .grade = final_grade,
      is_blank_outcome = is.na(.grade) | .grade == "",
      is_early_drop = registration_status_code %in% STATUS_DROP_EARLY | .grade == "Drop",
      is_late_withdrawal = !is_early_drop &
        (registration_status_code %in% STATUS_DROP_LATE | .grade == "W"),
      is_pass = !is_early_drop & !is_late_withdrawal &
        !is_blank_outcome & .grade %in% passing_grades,
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
  classified <- classify_attempt_outcomes(attempts)
  summarize_attempt_outcomes(classified, group_cols = group_cols, min_n = min_n)
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
    dplyr::filter(!is.na(final_grade), final_grade != "") %>%
    dplyr::mutate(grade_group = dplyr::case_when(
      final_grade %in% c("A", "A+", "A-", "RA", "RA+", "RA-") ~ "A",
      final_grade %in% c("B", "B+", "B-", "RB", "RB+", "RB-") ~ "B",
      final_grade %in% c("C", "C+", "C-", "CR", "RC", "RC+", "RC-", "RCR") ~ "C",
      final_grade %in% c("D", "D+", "D-", "RD", "RD+", "RD-") ~ "D",
      final_grade %in% c("F", "RF") ~ "F",
      final_grade == "W" ~ "W",
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
