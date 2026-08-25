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




# ── 2. Course Sequence Effect ─────────────────────────────────────────────────

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
    stop("[course-impact.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus
  data_edges <- data_edges %||% opt$data_edges %||% cedar_data_edges(students)
  analysis_end_term <- cedar_longitudinal_edge(data_edges, grade_dependent = TRUE)
  if (is.null(analysis_end_term)) {
    stop("[course-impact.R] No complete term with sufficiently complete grades is available.")
  }

  message("[course-impact.R] get_course_sequence_effect: ", course_x, " → ", course_y)

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
    stop("[course-impact.R] No students found for course_y: ", course_y)

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
    stop("[course-impact.R] Groups too small (min_n = ", min_n, "). ",
         "Try a different course pair or lower min_n.")

  # Summarize the term range and gap distribution for transparency
  term_range_x <- range(
    passed_x$term_x[passed_x$student_id %in% treatment_ids], na.rm = TRUE
  )
  term_range_y <- range(took_y$term_y)

  message("[course-impact.R]   Took ", course_x, " before ", course_y, ": ",
          length(treatment_ids), " students")
  message("[course-impact.R]   ", course_x, " offered: ", term_range_x[1], "–", term_range_x[2])
  message("[course-impact.R]   ", course_y, " offered: ", term_range_y[1], "–", term_range_y[2])
  message("[course-impact.R]   Took ", course_y, " without prior ", course_x, ": ",
          length(pool_ids), " students")
  message("[course-impact.R]   Note: treatment requires passing (not just taking) ", course_x)

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
      message("[course-impact.R]   GPA band requested but high_school_cum_gpa not available ",
              "(cedar_applicants may not be loaded) — skipping GPA filter.")
    } else {
      before <- nrow(groups)
      n_missing_hs_gpa_excluded <- sum(is.na(groups$high_school_cum_gpa))
      groups <- filter(groups, !is.na(high_school_cum_gpa))
      if (!is.null(hs_gpa_min))
        groups <- filter(groups, high_school_cum_gpa >= hs_gpa_min)
      if (!is.null(hs_gpa_max))
        groups <- filter(groups, high_school_cum_gpa <= hs_gpa_max)
      message("[course-impact.R]   GPA band [", hs_gpa_min %||% "-∞", ", ",
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
    stop("[course-impact.R] Groups too small after filtering (treatment=", n_t,
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
#'     \item{course_y}{Character. The downstream outcome course. May name
#'       several courses, in which case the analysis becomes a rollup across all
#'       of them and each student is counted once, at their earliest enrolment
#'       in the set. Required.}
#'     \item{campus}{Character vector. Optional campus filter.}
#'     \item{min_n}{Integer. Minimum students per instructor who later took Y
#'       (default 15). Instructors below this threshold are excluded.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course_x, course_y}{Course identifiers.}
#'     \item{outcomes}{Eligibility, continuation, and observed Y outcomes by
#'       each student's first instructor in X.}
#'     \item{order_audit_by_year}{Course-level yearly counts of students who
#'       passed Y strictly before or in the same term as their first X attempt.}
#'     \item{course_summary}{Course-level continuation denominator and rate,
#'       independent of instructor attribution and display thresholds.}
#'     \item{instructor_counts}{Tibble: instructor_name, n (students who took Y).}
#'     \item{balance}{Balance between the two most-common instructors' student pools.}
#'     \item{n_treatment, n_control}{Sizes for the reference instructor comparison.}
#'   }
#' @param data_edges Optional output of [cedar_data_edges()]. When omitted it is
#'   derived from `students`. X cohorts stop at `last_enrolled_complete`; grade
#'   outcomes stop at the earlier of that edge and `last_graded`. Cohorts without
#'   one subsequent regular term before the complete-enrollment edge are excluded
#'   from the continuation denominator.
get_instructor_effect <- function(students, programs, applicants = NULL,
                                   opt = list(), term_credits = NULL,
                                   data_edges = NULL) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || length(course_y) == 0)
    stop("[course-impact.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus

  data_edges <- data_edges %||% cedar_data_edges(students)
  observation_end_term <- cedar_longitudinal_edge(
    data_edges, grade_dependent = FALSE
  )
  analysis_end_term <- cedar_longitudinal_edge(data_edges, grade_dependent = TRUE)
  if (is.null(observation_end_term) || is.null(analysis_end_term)) {
    stop("[course-impact.R] No complete term with sufficiently complete grades is available.")
  }

  # course_y may name several courses — the department rollup passes every
  # follow-on course at once so a chair can ask "how do my instructors' students
  # do in our later courses" without first guessing which one to look at.
  rollup     <- length(course_y) > 1L
  course_y_label <- if (rollup) {
    paste0(length(course_y), " follow-on courses")
  } else {
    course_y
  }

  message("[course-impact.R] get_instructor_effect: ", course_x, " \u2192 ",
          course_y_label)

  pair_audit <- get_downstream_pair_audit(
    students, course_x, course_y,
    opt = list(campus = campus, data_edges = data_edges)
  )
  if (nrow(pair_audit$summary) == 0) {
    stop("[course-impact.R] No course-level downstream cohort was available.")
  }

  # Students who took Y — include late drops (DG/DW) so they count as DFW outcomes
  took_y <- students %>%
    filter(
      subject_course %in% course_y,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      term <= analysis_end_term
  )
  if (!is.null(campus)) took_y <- filter(took_y, campus %in% .env$campus)
  # CAMPUS_ROLLUP: Y is one student-level follow-on outcome after campus scope.
  took_y <- took_y %>%
    distinct(student_id, term, subject_course, .keep_all = TRUE) %>%
    select(student_id, term_y = term, subject_course_y = subject_course,
           grade_y = final_grade, status_y = registration_status_code)



  if (nrow(took_y) == 0)
    stop("[course-impact.R] No students found for course_y: ", course_y_label)

  # First instructor each student had in X
  x_instructor_rows <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      term <= observation_end_term,
      !is.na(instructor_name), nzchar(instructor_name)
    )
  if (!is.null(campus)) {
    x_instructor_rows <- filter(x_instructor_rows, campus %in% .env$campus)
  }

  # The downstream outcome comparison assigns each student once, to their first
  # instructor in X, so a repeat does not appear under multiple instructors.
  # Course-order totals are computed separately above at course/year grain and
  # never attributed to faculty.
  x_by_instructor <- x_instructor_rows %>%
    group_by(student_id, instructor_name) %>%
    arrange(term) %>%
    slice(1) %>%
    ungroup() %>%
    select(student_id, instructor_name, term_x = term)

  x_instructor <- x_by_instructor %>%
    group_by(student_id) %>%
    arrange(term_x) %>%
    slice(1) %>%
    ungroup() %>%
    add_next_term_col(term_x, summer = FALSE) %>%
    rename(first_followup_term = next_term)

  # A continuation denominator needs an opportunity to continue. Students
  # whose next regular term falls after the complete-enrollment edge are
  # right-censored; they
  # remain visible in the audit but cannot be treated as non-continuers.
  #
  # For a single named Y, a student who passed it before X was never eligible
  # to progress from X to Y. A same-term pass is shown separately because it is
  # concurrent, not prior. In a multi-course rollup, passing one member of the
  # set does not establish ineligibility for the others, so prior completion is
  # descriptive only and is not removed from the denominator.
  prior_y <- took_y %>%
    filter(grade_y %in% GRADES_PASS) %>%
    inner_join(select(x_instructor, student_id, term_x), by = "student_id") %>%
    group_by(student_id) %>%
    summarize(
      passed_y_before_x = any(term_y < term_x),
      passed_y_same_term = any(term_y == term_x),
      .groups = "drop"
    )

  x_eligibility <- x_instructor %>%
    left_join(prior_y, by = "student_id") %>%
    mutate(
      passed_y_before_x = coalesce(passed_y_before_x, FALSE),
      passed_y_same_term = coalesce(passed_y_same_term, FALSE),
      right_censored = is.na(first_followup_term) |
        first_followup_term > observation_end_term,
      prior_pass_excluded = !rollup & passed_y_before_x,
      eligible_for_y = !right_censored & !prior_pass_excluded
    )

  eligibility_counts <- x_eligibility %>%
    group_by(instructor_name) %>%
    summarize(
      n_total_in_x = n(),
      n_right_censored = sum(right_censored),
      n_passed_y_before_x = sum(passed_y_before_x),
      n_passed_y_same_term = sum(passed_y_same_term),
      n_eligible_for_y = sum(eligible_for_y),
      .groups = "drop"
    )

  eligible_x <- filter(x_eligibility, eligible_for_y)

  # Students who took X before Y, with their instructor
  instructor_data <- took_y %>%
    inner_join(select(eligible_x, student_id, instructor_name, term_x),
               by = "student_id") %>%
    filter(term_x < term_y)

  # One row per student: their earliest follow-on enrolment *that comes after X*.
  #
  # This has to run after the term_x < term_y filter above, not before it. A
  # department's follow-on set usually contains a co-requisite lab taken in the
  # same term as X; deduplicating first would pick that lab as the student's
  # earliest row, the filter would then discard it, and the student would vanish
  # despite having taken later courses.
  #
  # It applies to a single course_y as well, not just the rollup. n_took_y is
  # labelled "students" in the UI, but without this it counted enrolments: a
  # student who failed the downstream course and retook it appeared twice, once
  # failing and once passing. For CHEM 1215 -> CHEM 1225 that was 3,593 rows
  # against 3,209 students, so 283 repeaters were double-weighted and the pass
  # rate was computed over attempts while being presented as students.
  instructor_data <- instructor_data %>%
    group_by(student_id) %>%
    arrange(term_y) %>%
    slice(1) %>%
    ungroup()

  if (nrow(instructor_data) == 0)
    stop("[course-impact.R] No students found who took ", course_x,
         " before ", course_y_label, ".")

  # Total students in X per instructor (all students, not just those who took Y).
  # This must use the same one-row-per-student X attribution as the analysis
  # itself; otherwise repeat attempts in X make pct_took_y divide students by
  # enrollments while the UI labels both sides as students.
  term_range_x <- range(eligible_x$term_x)
  term_range_y <- range(took_y$term_y)

  # Keep only instructors with enough downstream students
  instructor_counts <- instructor_data %>%
    count(instructor_name, sort = TRUE) %>%
    rename(n_took_y = n) %>%
    filter(n_took_y >= min_n)

  if (nrow(instructor_counts) < 2) {
    n_inst_any <- dplyr::n_distinct(instructor_data$instructor_name)
    stop("Fewer than 2 instructors have ≥ ", min_n,
         " students who later took ", course_y_label, ". ",
         n_inst_any, " instructor(s) had any such students at all. ",
         "Lower 'Min students per instructor' (currently ", min_n, ") to see results.")
  }

  instructor_data <- filter(instructor_data,
                             instructor_name %in% instructor_counts$instructor_name)

  # Grade outcomes in Y by instructor — wide format (one row per instructor).
  # Three mutually exclusive *observed* outcomes:
  #   dropped = late drop (DG/DW registration status)
  #   failed  = registered with any recorded nonpassing outcome
  #   pass    = A+ through C or CR
  # Blank and audit grades remain in the continuation count but are excluded
  # from every grade-rate denominator. I, NC, NR, P, and S are nonpassing.
  observed_outcomes <- instructor_data %>%
    mutate(registration_status_code = status_y, final_grade = grade_y) %>%
    classify_enrollment_outcomes() %>%
    mutate(outcome = case_when(
      outcome == "pass" ~ "pass",
      status_y %in% STATUS_DROP_LATE ~ "dropped",
      TRUE ~ "failed"
    ))

  outcome_counts <- observed_outcomes %>%
    group_by(instructor_name, outcome) %>%
    summarize(n = n(), .groups = "drop")

  outcomes_long <- tidyr::crossing(
      instructor_name = instructor_counts$instructor_name,
      outcome = c("pass", "failed", "dropped")
    ) %>%
    left_join(outcome_counts, by = c("instructor_name", "outcome")) %>%
    mutate(n = coalesce(n, 0L)) %>%
    group_by(instructor_name) %>%
    mutate(pct = if (sum(n) > 0) round(100 * n / sum(n), 1) else NA_real_) %>%
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
    left_join(eligibility_counts, by = "instructor_name") %>%
    mutate(
      n_outcome_observed = n_pass + n_failed + n_dropped,
      n_outcome_unobserved = n_took_y - n_outcome_observed,
      pct_took_y = round(100 * n_took_y / n_eligible_for_y, 1),
      pct_dfw    = round(100 * (n_failed + n_dropped) / n_outcome_observed, 1)
    ) %>%
    dplyr::select(
      instructor_name,
      n_total_in_x,
      n_right_censored,
      n_passed_y_before_x,
      n_passed_y_same_term,
      n_eligible_for_y,
      n_took_y,
      pct_took_y,
      n_outcome_observed,
      n_outcome_unobserved,
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
    students      = students,
    term_credits  = term_credits
  )

  message("[course-impact.R]   Instructor effect computed. Done.")

  list(
    course_x              = course_x,
    course_y              = course_y,
    course_y_label        = course_y_label,
    rollup                = rollup,
    n_courses_y           = length(course_y),
    outcomes              = outcomes,
    order_audit_by_year   = pair_audit$order_by_year,
    course_summary        = pair_audit$summary,
    instructor_counts     = instructor_counts,
    balance               = comparison$balance,
    n_treatment           = comparison$n_treatment,
    n_control             = comparison$n_control,
    reference_instructor  = ref_instructor,
    comparison_instructor = cmp_instructor,
    term_range_x          = term_range_x,
    term_range_y          = term_range_y,
    analysis_end_term     = analysis_end_term,
    observation_end_term  = observation_end_term,
    edge_note             = cedar_longitudinal_edge_note(
      data_edges, grade_dependent = TRUE
    ),
    prior_pass_exclusion_applied = !rollup,
    eligibility_audit     = outcomes %>%
      summarize(
        n_total_in_x = sum(n_total_in_x),
        n_right_censored = sum(n_right_censored),
        n_passed_y_before_x = sum(n_passed_y_before_x),
        n_passed_y_same_term = sum(n_passed_y_same_term),
        n_eligible_for_y = sum(n_eligible_for_y),
        n_took_y = sum(n_took_y),
        n_outcome_observed = sum(n_outcome_observed),
        n_outcome_unobserved = sum(n_outcome_unobserved)
      )
  )
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
