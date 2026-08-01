# course-impact.R — Course Impact Analysis
#
# Observational comparisons of student outcomes between a "treatment" group
# (took a course, had a specific instructor, followed a course sequence) and a
# comparable control group. All analyses call build_comparison() (branches/comparison.R)
# for covariate joining and balance reporting.
#
# Two question types:
#
#   (A RETENTION analysis, get_course_retention(), was removed 2026-08-01: it had
#   no callers, and its private .compute_retention() was shadowed at load time by
#   a same-named function in cones/course-retention.R. Course Dynamics > Retention
#   is served by get_retention_trend() in that file.)
#
#   1. SEQUENCE — get_course_sequence_effect()
#      Do students who took course X before course Y earn better grades in Y?
#      Treatment: passed X before enrolling in Y. Control: took Y without prior X.
#      Outcome: pass/DFW rate in Y.
#
#   2. INSTRUCTOR — get_instructor_effect()
#      Did instructor A's students in course X outperform instructor B's when
#      they later took course Y?
#      Treatment: had instructor A in X, then took Y. Control: had instructor B.
#      Outcome: pass/DFW rate in Y.
#
# Interactive covariate filters (opt$filters) narrow the comparison pool after
# group assignment so users can see how the result changes under different
# comparability assumptions — without rebuilding groups from scratch.
#
# Depends on: build_comparison(), compute_balance() (branches/comparison.R)
#             STATUS_REGISTERED (lists/status_codes.R)
#             GRADES_DFW, GRADES_PASS (lists/grades.R)

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ── Internal helpers ──────────────────────────────────────────────────────────

# NOTE: a private .advance_n_terms() lived here until 2026-08-01. It duplicated
# add_next_term_col() (R/trunk/utils.R) and got the summer case wrong
# (202460 + 70 = 202530, a code with no season). It went unnoticed because its
# only caller was the removed retention analysis. The canonical helper handles
# Summer -> Fall correctly and is what the live retention path uses.

# Apply a named list of covariate equality filters to a groups tibble.
# Students with NA in the filtered column are excluded.
# Example: filters = list(first_gen = TRUE, pell_eligible = TRUE)
.apply_covariate_filters <- function(groups, filters) {
  for (col in names(filters)) {
    val <- filters[[col]]
    if (!col %in% names(groups)) {
      message("[course-impact.R] Filter column '", col, "' not in groups — skipping.")
      next
    }
    groups <- filter(groups, !is.na(.data[[col]]) & .data[[col]] == val)
  }
  groups
}


# Summarize group covariates into a compact profile table.
# inst_gpa and overall_credits_earned are drawn from each student's covariate_term
# (the term they took course X for treatment, course Y for control) rather than
# their entry term, so these reflect academic standing at the point of comparison.
.group_profile <- function(groups) {
  groups %>%
    group_by(group) %>%
    summarize(
      n                    = n(),
      pct_first_gen        = round(100 * mean(first_gen,     na.rm = TRUE), 1),
      pct_pell             = round(100 * mean(pell_eligible, na.rm = TRUE), 1),
      mean_hs_gpa          = if ("high_school_cum_gpa"    %in% names(.))
                               round(mean(high_school_cum_gpa,    na.rm = TRUE), 2) else NA_real_,
      mean_act             = if ("unm_act_combined_score" %in% names(.))
                               round(mean(unm_act_combined_score, na.rm = TRUE), 1) else NA_real_,
      mean_inst_gpa        = round(mean(inst_gpa,              na.rm = TRUE), 2),
      mean_credits_earned  = if ("overall_credits_earned" %in% names(.))
                               round(mean(overall_credits_earned, na.rm = TRUE), 1) else NA_real_,
      .groups = "drop"
    )
}




# ── 2. Course Sequence Effect ─────────────────────────────────────────────────

#' Course Sequence Effect
#'
#' Compares grades in course Y between students who passed course X before
#' taking Y (treatment) and students who took Y without prior X (control).
#' Surfaces whether completing X meaningfully prepares students for Y.
#'
#' @param students cedar_students data frame.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The preparatory course. Required.}
#'     \item{course_y}{Character. The outcome course. Required.}
#'     \item{campus}{Character vector. Optional campus filter.}
#'     \item{min_n}{Integer. Minimum students per group (default 15).}
#'     \item{filters}{Named list of covariate equality filters. Optional.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course_x, course_y}{Course identifiers.}
#'     \item{outcomes}{Tibble: group, outcome (pass/dfw), n, pct.}
#'     \item{group_profile}{Compact covariate summary per group.}
#'     \item{balance}{From compute_balance().}
#'     \item{n_treatment, n_control}{Group sizes.}
#'   }
get_course_sequence_effect <- function(students, programs, applicants = NULL,
                                       opt = list()) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || is.null(course_y))
    stop("[course-impact.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus

  message("[course-impact.R] get_course_sequence_effect: ", course_x, " → ", course_y)

  # Students who took Y (registered, with a gradeable outcome)
  took_y <- students %>%
    filter(
      subject_course %in% course_y,
      registration_status_code %in% STATUS_REGISTERED
    )
  if (!is.null(campus)) took_y <- filter(took_y, campus %in% .env$campus)
  took_y <- took_y %>%
    distinct(student_id, term, .keep_all = TRUE) %>%
    select(student_id, term_y = term, grade_y = final_grade)

  if (nrow(took_y) == 0)
    stop("[course-impact.R] No students found for course_y: ", course_y)

  # When did each student first pass X?
  passed_x <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      final_grade %in% GRADES_PASS
    ) %>%
    group_by(student_id) %>%
    summarize(term_x = min(term), .groups = "drop")

  # Label treatment (passed X strictly before taking Y) vs. control (took Y, no prior X)
  sequence_data <- took_y %>%
    left_join(passed_x, by = "student_id") %>%
    mutate(
      group = if_else(!is.na(term_x) & term_x < term_y, "treatment", "control")
    )

  treatment_ids <- filter(sequence_data, group == "treatment") %>% pull(student_id) %>% unique()
  pool_ids      <- filter(sequence_data, group == "control")   %>% pull(student_id) %>% unique()

  # Summarize the term range and gap distribution for transparency
  treatment_terms <- sequence_data %>%
    filter(group == "treatment") %>%
    mutate(terms_gap = term_y - term_x)

  term_range_x <- range(filter(students, student_id %in% treatment_ids,
                                subject_course %in% course_x)$term)
  term_range_y <- range(took_y$term_y)

  message("[course-impact.R]   Took ", course_x, " before ", course_y, ": ",
          length(treatment_ids), " students")
  message("[course-impact.R]   ", course_x, " offered: ", term_range_x[1], "–", term_range_x[2])
  message("[course-impact.R]   ", course_y, " offered: ", term_range_y[1], "–", term_range_y[2])
  message("[course-impact.R]   Took ", course_y, " without prior ", course_x, ": ",
          length(pool_ids), " students")
  message("[course-impact.R]   Note: treatment requires passing (not just taking) ", course_x)

  if (length(treatment_ids) < min_n || length(pool_ids) < min_n)
    stop("[course-impact.R] Groups too small (min_n = ", min_n, "). ",
         "Try a different course pair or lower min_n.")

  # Build per-student covariate terms: treatment uses the term they took X,
  # control uses the term they took Y. This gives a meaningful GPA/credits
  # snapshot at the moment of comparison, not at their entry term years earlier.
  covariate_terms <- bind_rows(
    sequence_data %>%
      filter(group == "treatment") %>%
      transmute(student_id, covariate_term = as.integer(term_x)),
    sequence_data %>%
      filter(group == "control") %>%
      transmute(student_id, covariate_term = as.integer(term_y))
  ) %>%
    distinct(student_id, .keep_all = TRUE)

  comparison <- build_comparison(
    treatment_ids   = treatment_ids,
    pool_ids        = pool_ids,
    programs        = programs,
    applicants      = applicants,
    students        = students,
    covariate_terms = covariate_terms
  )
  groups <- comparison$groups

  # ── GPA band filter ──────────────────────────────────────────────────────────
  # HS GPA is often imbalanced in sequence analyses because stronger students
  # self-select into completing prerequisites. Restricting both groups to a
  # common GPA window makes the comparison more defensible.
  # opt$hs_gpa_min / opt$hs_gpa_max are optional; NULL means no restriction.
  hs_gpa_min <- opt$hs_gpa_min
  hs_gpa_max <- opt$hs_gpa_max
  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max)) {
    if (!"high_school_cum_gpa" %in% names(groups)) {
      message("[course-impact.R]   GPA band requested but high_school_cum_gpa not available ",
              "(cedar_applicants may not be loaded) — skipping GPA filter.")
    } else {
      before <- nrow(groups)
      if (!is.null(hs_gpa_min))
        groups <- filter(groups, is.na(high_school_cum_gpa) | high_school_cum_gpa >= hs_gpa_min)
      if (!is.null(hs_gpa_max))
        groups <- filter(groups, is.na(high_school_cum_gpa) | high_school_cum_gpa <= hs_gpa_max)
      message("[course-impact.R]   GPA band [", hs_gpa_min %||% "-∞", ", ",
              hs_gpa_max %||% "+∞", "]: ", before, " → ", nrow(groups), " students")
    }
  }

  filters <- opt$filters %||% list()
  if (length(filters) > 0)
    groups <- .apply_covariate_filters(groups, filters)

  n_t <- sum(groups$group == "treatment")
  n_c <- sum(groups$group == "control")
  if (n_t < min_n || n_c < min_n)
    stop("[course-impact.R] Groups too small after filtering (treatment=", n_t,
         ", control=", n_c, ", min_n=", min_n, ").")

  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max) || length(filters) > 0) {
    comparison$balance     <- compute_balance(groups)
    comparison$n_treatment <- n_t
    comparison$n_control   <- n_c
  }

  # Grade outcomes in Y by group.
  # sequence_data already carries the group label — use it directly, restricted
  # to students that survived build_comparison() (those with program records).
  outcomes <- sequence_data %>%
    filter(student_id %in% groups$student_id) %>%
    mutate(
      outcome = case_when(
        grade_y %in% GRADES_PASS ~ "pass",
        grade_y %in% GRADES_DFW  ~ "dfw",
        TRUE                      ~ NA_character_
      )
    ) %>%
    filter(!is.na(outcome)) %>%
    group_by(group, outcome) %>%
    summarize(n = n(), .groups = "drop") %>%
    group_by(group) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  # Count how many treatment students were dropped by build_comparison()
  # (students without program records don't make it into groups)
  n_dropped_by_programs <- length(treatment_ids) - comparison$n_treatment

  message("[course-impact.R]   Sequence effect computed. Done.")

  list(
    course_x                = course_x,
    course_y                = course_y,
    outcomes                = outcomes,
    group_profile           = .group_profile(groups),
    balance                 = comparison$balance,
    n_treatment             = comparison$n_treatment,
    n_control               = comparison$n_control,
    n_took_x_before_y       = length(treatment_ids),
    n_took_y_without_x      = length(pool_ids),
    n_dropped_by_programs   = n_dropped_by_programs,
    term_range_x            = term_range_x,
    term_range_y            = term_range_y
  )
}


# ── 3. Downstream Success by Instructor ───────────────────────────────────────

#' Downstream Success by Instructor
#'
#' Among students who took course X and later took course Y, compares grade
#' outcomes in Y between students taught by different instructors in X.
#' Surfaces descriptive differences in downstream outcomes by upstream instructor.
#'
#' The balance table reveals whether instructor sections self-selected different
#' kinds of students — the most common confounder in multi-section courses.
#'
#' @param students cedar_students data frame.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The upstream course. Required.}
#'     \item{course_y}{Character. The downstream outcome course. Required.}
#'     \item{campus}{Character vector. Optional campus filter.}
#'     \item{min_n}{Integer. Minimum students per instructor who later took Y
#'       (default 15). Instructors below this threshold are excluded.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course_x, course_y}{Course identifiers.}
#'     \item{outcomes}{Tibble: instructor_name, outcome, n, total, pct.}
#'     \item{instructor_counts}{Tibble: instructor_name, n (students who took Y).}
#'     \item{balance}{Balance between the two most-common instructors' student pools.}
#'     \item{n_treatment, n_control}{Sizes for the reference instructor comparison.}
#'   }
get_instructor_effect <- function(students, programs, applicants = NULL,
                                   opt = list()) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || is.null(course_y))
    stop("[course-impact.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus

  message("[course-impact.R] get_instructor_effect: ", course_x, " → ", course_y)

  # Students who took Y — include late drops (DG/DW) so they count as DFW outcomes
  took_y <- students %>%
    filter(
      subject_course %in% course_y,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)
    )
  if (!is.null(campus)) took_y <- filter(took_y, campus %in% .env$campus)
  took_y <- took_y %>%
    distinct(student_id, term, .keep_all = TRUE) %>%
    select(student_id, term_y = term, grade_y = final_grade,
           status_y = registration_status_code)

  if (nrow(took_y) == 0)
    stop("[course-impact.R] No students found for course_y: ", course_y)

  # First instructor each student had in X
  x_instructor <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      !is.na(instructor_name), nzchar(instructor_name)
    )
  if (!is.null(campus)) x_instructor <- filter(x_instructor, campus %in% .env$campus)
  x_instructor <- x_instructor %>%
    group_by(student_id) %>%
    arrange(term) %>%
    slice(1) %>%
    ungroup() %>%
    select(student_id, instructor_name, term_x = term)

  # Students who took X before Y, with their instructor
  instructor_data <- took_y %>%
    inner_join(x_instructor, by = "student_id") %>%
    filter(term_x < term_y)

  if (nrow(instructor_data) == 0)
    stop("[course-impact.R] No students found who took ", course_x,
         " before ", course_y, ".")

  # Total enrollment in X per instructor (all students, not just those who took Y).
  # This gives context for how many students each instructor has taught overall,
  # vs. n_took_y which is only the subset who later enrolled in the downstream course.
  total_enrl_in_x <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      !is.na(instructor_name), nzchar(instructor_name)
    ) %>%
    { if (!is.null(campus)) filter(., campus %in% .env$campus) else . } %>%
    count(instructor_name, name = "n_total_in_x")

  term_range_x <- range(x_instructor$term_x)
  term_range_y <- range(took_y$term_y)

  # Keep only instructors with enough downstream students
  instructor_counts <- instructor_data %>%
    count(instructor_name, sort = TRUE) %>%
    rename(n_took_y = n) %>%
    filter(n_took_y >= min_n)

  if (nrow(instructor_counts) < 2) {
    n_inst_any <- dplyr::n_distinct(instructor_data$instructor_name)
    stop("Fewer than 2 instructors have ≥ ", min_n,
         " students who later took ", course_y, ". ",
         n_inst_any, " instructor(s) had any such students at all. ",
         "Lower 'Min students per instructor' (currently ", min_n, ") to see results.")
  }

  instructor_data <- filter(instructor_data,
                             instructor_name %in% instructor_counts$instructor_name)

  # Grade outcomes in Y by instructor — wide format (one row per instructor).
  # Three mutually exclusive outcomes (sum to n_took_y):
  #   dropped = late drop (DG/DW registration status)
  #   failed  = registered to end but grade was not a pass (D, F, W, I, NR, NC, etc.)
  #   pass    = C- or better, CR, P, S
  # pct_dfw = (n_dropped + n_failed) / n_took_y
  outcomes_long <- instructor_data %>%
    mutate(
      outcome = case_when(
        status_y %in% STATUS_DROP_LATE ~ "dropped",
        grade_y %in% GRADES_PASS       ~ "pass",
        TRUE                           ~ "failed"
      )
    ) %>%
    group_by(instructor_name, outcome) %>%
    summarize(n = n(), .groups = "drop") %>%
    group_by(instructor_name) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  outcomes_wide <- outcomes_long %>%
    tidyr::pivot_wider(
      id_cols     = "instructor_name",
      names_from  = "outcome",
      values_from = c("n", "pct"),
      values_fill = 0
    )
  for (.col in c("n_pass", "pct_pass", "n_failed", "pct_failed", "n_dropped", "pct_dropped")) {
    if (!.col %in% names(outcomes_wide)) outcomes_wide[[.col]] <- 0
  }

  outcomes <- outcomes_wide %>%
    left_join(instructor_counts, by = "instructor_name") %>%
    left_join(total_enrl_in_x,   by = "instructor_name") %>%
    mutate(
      pct_took_y = round(100 * n_took_y / n_total_in_x, 1),
      pct_dfw    = round(100 * (n_failed + n_dropped) / n_took_y, 1)
    ) %>%
    dplyr::select(
      instructor_name,
      n_total_in_x,
      n_took_y,
      pct_took_y,
      n_pass, pct_pass,
      n_failed, pct_failed,
      n_dropped, pct_dropped,
      pct_dfw
    ) %>%
    arrange(desc(n_took_y))

  message("[course-impact.R]   Instructors with enough students: ",
          nrow(instructor_counts))

  # Balance: reference instructor vs. second-most-common instructor.
  # Pairwise comparison is more interpretable than one vs. everyone —
  # "everyone else" conflates multiple instructors with different student mixes.
  ref_instructor <- opt$reference_instructor %||% instructor_counts$instructor_name[1]
  cmp_instructor <- instructor_counts$instructor_name[
    instructor_counts$instructor_name != ref_instructor
  ][1]
  treatment_ids  <- filter(instructor_data, instructor_name == ref_instructor)$student_id
  pool_ids       <- filter(instructor_data, instructor_name == cmp_instructor)$student_id

  message("[course-impact.R]   Balance: ", ref_instructor, " vs. ", cmp_instructor,
          " (", length(treatment_ids), " vs. ", length(pool_ids), " students)")
  if (nrow(instructor_counts) > 2) {
    message("[course-impact.R]   Note: ", nrow(instructor_counts) - 2,
            " additional instructor(s) excluded from balance check.")
  }

  comparison <- build_comparison(
    treatment_ids = treatment_ids,
    pool_ids      = pool_ids,
    programs      = programs,
    applicants    = applicants,
    students      = students
  )

  message("[course-impact.R]   Instructor effect computed. Done.")

  list(
    course_x              = course_x,
    course_y              = course_y,
    outcomes              = outcomes,
    instructor_counts     = instructor_counts,
    balance               = comparison$balance,
    n_treatment           = comparison$n_treatment,
    n_control             = comparison$n_control,
    reference_instructor  = ref_instructor,
    comparison_instructor = cmp_instructor,
    term_range_x          = term_range_x,
    term_range_y          = term_range_y
  )
}
