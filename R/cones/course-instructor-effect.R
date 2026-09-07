# course-instructor-effect.R — Downstream Success by Instructor
#
# Among students who took course X and later took course Y, did the students of
# one X instructor do better in Y than another's?
#
#   Treatment: had the reference instructor in X, then took Y.
#   Control:   had the comparison instructor in X, then took Y.
#   Outcome:   pass / failed / late drop in Y.
#
# Descriptive, not causal. The balance table exists to expose the usual
# confounder in a multi-section course: instructor sections self-select
# different kinds of students, and that shows up downstream as an instructor
# effect. Balance is computed pairwise — reference vs. the second-largest
# instructor — because pooling "everyone else" conflates instructors with
# different student mixes.
#
# course_y may name several courses. The department rollup passes a whole
# follow-on set at once, and each student is counted once, at their earliest
# enrolment in the set that comes after X.
#
# Two right edges are in play: the X cohort stops at last_enrolled_complete so
# that a student still has an opportunity to continue, and Y grade outcomes stop
# at the grade edge. See the right-edge policy in AGENTS.md.
#
# Split from the former cones/course-impact.R on 2026-09-07. The sequence
# question that shared that file now lives in cones/course-sequence-effect.R;
# the two shared no code, only a filename.
#
# Depends on: build_comparison() (branches/comparison.R)
#             get_downstream_pair_audit() (branches/course-flows.R)
#             classify_enrollment_outcomes(), add_next_term_col() (trunk/utils.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             STATUS_REGISTERED, STATUS_DROP_LATE (lists/status_codes.R)
#             GRADES_PASS (lists/grades.R)


# ── Downstream Success by Instructor ──────────────────────────────────────────

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
    stop("[course-instructor-effect.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus

  data_edges <- data_edges %||% cedar_data_edges(students)
  observation_end_term <- cedar_longitudinal_edge(
    data_edges, grade_dependent = FALSE
  )
  analysis_end_term <- cedar_longitudinal_edge(data_edges, grade_dependent = TRUE)
  if (is.null(observation_end_term) || is.null(analysis_end_term)) {
    stop("[course-instructor-effect.R] No complete term with sufficiently complete grades is available.")
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

  message("[course-instructor-effect.R] get_instructor_effect: ", course_x, " \u2192 ",
          course_y_label)

  pair_audit <- get_downstream_pair_audit(
    students, course_x, course_y,
    opt = list(campus = campus, data_edges = data_edges)
  )
  if (nrow(pair_audit$summary) == 0) {
    stop("[course-instructor-effect.R] No course-level downstream cohort was available.")
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
    stop("[course-instructor-effect.R] No students found for course_y: ", course_y_label)

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
    stop("[course-instructor-effect.R] No students found who took ", course_x,
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

  message("[course-instructor-effect.R]   Instructors with enough students: ",
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

  message("[course-instructor-effect.R]   Balance: ", ref_instructor, " vs. ", cmp_instructor,
          " (", length(treatment_ids), " vs. ", length(pool_ids), " students)")
  if (nrow(instructor_counts) > 2) {
    message("[course-instructor-effect.R]   Note: ", nrow(instructor_counts) - 2,
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

  message("[course-instructor-effect.R]   Instructor effect computed. Done.")

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
