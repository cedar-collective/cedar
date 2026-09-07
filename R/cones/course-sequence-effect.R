# course-sequence-effect.R — Course Sequence Effect
#
# Do students who took course X before course Y earn better grades in Y?
#
#   Treatment: passed X strictly before their first classifiable Y attempt.
#   Control:   took Y with no prior in-scope X pass.
#   Outcome:   pass/DFW in that one selected Y attempt.
#
# An observational comparison, never a causal estimate. Students self-select
# into completing prerequisites, so build_comparison() (branches/comparison.R)
# joins the covariates and compute_balance() reports how comparable the two
# groups actually are. The optional HS GPA band and the interactive covariate
# filters (opt$filters) narrow the pool *after* group assignment, so a user can
# watch the result move under different comparability assumptions without
# rebuilding the groups from scratch.
#
# Split from the former cones/course-impact.R on 2026-09-07. The instructor
# question that shared that file now lives in cones/course-instructor-effect.R;
# the two shared no code, only a filename.
#
#   (A RETENTION analysis, get_course_retention(), was removed 2026-08-01: it had
#   no callers, and its private .compute_retention() was shadowed at load time by
#   a same-named function in cones/course-retention.R. Course Dynamics > Retention
#   is served by get_retention_trend() in that file.)
#
# Depends on: build_comparison(), compute_balance() (branches/comparison.R)
#             classify_enrollment_outcomes() (trunk/utils.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             STATUS_REGISTERED, STATUS_DROP_LATE (lists/status_codes.R)

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
      message("[course-sequence-effect.R] Filter column '", col, "' not in groups — skipping.")
      next
    }
    groups <- filter(groups, !is.na(.data[[col]]) & .data[[col]] == val)
  }
  groups
}


# Summarize group covariates into a compact profile table.
#
# The academic-position figures are RECONSTRUCTED at each student's covariate_term
# (the term they took course X for treatment, course Y for control), not read off
# cedar_programs. The cumulative fields there are stamped at the data pull, so
# they describe where a student ended up rather than where they stood at the
# point of comparison — see .attach_position_covariates() in branches/comparison.R
# and the field reliability contract in AGENTS.md.
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
      mean_cum_gpa         = if ("cum_gpa_entering" %in% names(.))
                               round(mean(cum_gpa_entering, na.rm = TRUE), 2) else NA_real_,
      # Descriptive companion: where the two groups ended up overall. Much better
      # covered than the reconstruction, and NOT a matching covariate — it is
      # measured after the outcome. See comparison.R.
      mean_current_gpa     = if ("current_unm_gpa" %in% names(.))
                               round(mean(current_unm_gpa, na.rm = TRUE), 2) else NA_real_,
      mean_credits_earned  = if ("total_credits_entering" %in% names(.))
                               round(mean(total_credits_entering, na.rm = TRUE), 1) else NA_real_,
      .groups = "drop"
    )
}




# ── Course Sequence Effect ────────────────────────────────────────────────────

#' Course Sequence Effect
#'
#' Compares grades in course Y between students who passed course X before
#' their first observed, classifiable Y attempt (treatment) and students whose
#' first such Y attempt occurred without a prior in-scope X pass (control).
#' Surfaces whether completing X meaningfully prepares students for Y.
#'
#' @param students cedar_students data frame.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param data_edges Optional output of [cedar_data_edges()]. Y outcomes stop at
#'   the longitudinal grade edge: the earlier of `last_enrolled_complete` and
#'   `last_graded`.
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
                                       opt = list(), term_credits = NULL,
                                       data_edges = NULL) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || is.null(course_y))
    stop("[course-sequence-effect.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus
  data_edges <- data_edges %||% opt$data_edges %||% cedar_data_edges(students)
  analysis_end_term <- cedar_longitudinal_edge(data_edges, grade_dependent = TRUE)
  if (is.null(analysis_end_term)) {
    stop("[course-sequence-effect.R] No complete term with sufficiently complete grades is available.")
  }

  message("[course-sequence-effect.R] get_course_sequence_effect: ", course_x, " → ", course_y)

  # Apply the delivery-campus scope once, before deriving either side of the
  # sequence. Otherwise an excluded-campus X pass can relabel an in-scope Y
  # student as treatment.
  scoped_students <- students %>%
    filter(term <= analysis_end_term)
  if (!is.null(campus)) {
    scoped_students <- scoped_students %>%
      filter(campus %in% .env$campus)
  }

  # Select one Y outcome per student: the earliest in-scope term with a
  # classifiable registered or late-drop outcome. Multiple CRNs in that term
  # collapse to one outcome, with any DFW taking precedence over a pass.
  took_y <- scoped_students %>%
    filter(
      subject_course %in% course_y,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)
    ) %>%
    distinct(student_id, term, crn, registration_status_code, final_grade,
             .keep_all = TRUE) %>%
    classify_enrollment_outcomes() %>%
    group_by(student_id, term) %>%
    summarize(
      y_outcome = if_else(any(outcome == "dfw"), "dfw", "pass"),
      .groups = "drop"
    ) %>%
    arrange(student_id, term) %>%
    group_by(student_id) %>%
    slice_head(n = 1L) %>%
    ungroup() %>%
    rename(term_y = term)

  if (nrow(took_y) == 0)
    stop("[course-sequence-effect.R] No students found for course_y: ", course_y)

  # When did each student first pass X inside the same campus and grade edge?
  passed_x <- scoped_students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)
    ) %>%
    classify_enrollment_outcomes() %>%
    filter(outcome == "pass") %>%
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

  if (length(treatment_ids) < min_n || length(pool_ids) < min_n)
    stop("[course-sequence-effect.R] Groups too small (min_n = ", min_n, "). ",
         "Try a different course pair or lower min_n.")

  # Summarize the term range and gap distribution for transparency
  term_range_x <- range(
    passed_x$term_x[passed_x$student_id %in% treatment_ids], na.rm = TRUE
  )
  term_range_y <- range(took_y$term_y)

  message("[course-sequence-effect.R]   Took ", course_x, " before ", course_y, ": ",
          length(treatment_ids), " students")
  message("[course-sequence-effect.R]   ", course_x, " offered: ", term_range_x[1], "–", term_range_x[2])
  message("[course-sequence-effect.R]   ", course_y, " offered: ", term_range_y[1], "–", term_range_y[2])
  message("[course-sequence-effect.R]   Took ", course_y, " without prior ", course_x, ": ",
          length(pool_ids), " students")
  message("[course-sequence-effect.R]   Note: treatment requires passing (not just taking) ", course_x)

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
    covariate_terms = covariate_terms,
    term_credits    = term_credits
  )
  groups <- comparison$groups
  n_dropped_by_programs <- length(treatment_ids) - comparison$n_treatment
  n_missing_hs_gpa_excluded <- 0L

  # ── GPA band filter ──────────────────────────────────────────────────────────
  # HS GPA is often imbalanced in sequence analyses because stronger students
  # self-select into completing prerequisites. Restricting both groups to a
  # common GPA window makes the comparison more defensible.
  # opt$hs_gpa_min / opt$hs_gpa_max are optional; NULL means no restriction.
  hs_gpa_min <- opt$hs_gpa_min
  hs_gpa_max <- opt$hs_gpa_max
  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max)) {
    if (!"high_school_cum_gpa" %in% names(groups)) {
      message("[course-sequence-effect.R]   GPA band requested but high_school_cum_gpa not available ",
              "(cedar_applicants may not be loaded) — skipping GPA filter.")
    } else {
      before <- nrow(groups)
      n_missing_hs_gpa_excluded <- sum(is.na(groups$high_school_cum_gpa))
      groups <- filter(groups, !is.na(high_school_cum_gpa))
      if (!is.null(hs_gpa_min))
        groups <- filter(groups, high_school_cum_gpa >= hs_gpa_min)
      if (!is.null(hs_gpa_max))
        groups <- filter(groups, high_school_cum_gpa <= hs_gpa_max)
      message("[course-sequence-effect.R]   GPA band [", hs_gpa_min %||% "-∞", ", ",
              hs_gpa_max %||% "+∞", "]: ", before, " → ", nrow(groups),
              " students; ", n_missing_hs_gpa_excluded, " missing GPA excluded")
    }
  }

  filters <- opt$filters %||% list()
  if (length(filters) > 0)
    groups <- .apply_covariate_filters(groups, filters)

  n_t <- sum(groups$group == "treatment")
  n_c <- sum(groups$group == "control")
  if (n_t < min_n || n_c < min_n)
    stop("[course-sequence-effect.R] Groups too small after filtering (treatment=", n_t,
         ", control=", n_c, ", min_n=", min_n, ").")

  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max) || length(filters) > 0) {
    comparison$balance     <- compute_balance(groups)
    comparison$n_treatment <- n_t
    comparison$n_control   <- n_c
  }

  # Grade outcomes in the single selected Y attempt, restricted to students
  # that survived covariate construction and optional filters.
  outcomes <- sequence_data %>%
    filter(student_id %in% groups$student_id) %>%
    transmute(student_id, group, outcome = y_outcome) %>%
    group_by(group, outcome) %>%
    summarize(n = n_distinct(student_id), .groups = "drop") %>%
    group_by(group) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  message("[course-sequence-effect.R]   Sequence effect computed. Done.")

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
    n_missing_hs_gpa_excluded = n_missing_hs_gpa_excluded,
    y_attempt_rule          = "earliest classifiable in-scope Y attempt per student",
    term_range_x            = term_range_x,
    term_range_y            = term_range_y,
    analysis_end_term       = analysis_end_term,
    edge_note               = cedar_longitudinal_edge_note(
      data_edges, grade_dependent = TRUE
    )
  )
}

# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
