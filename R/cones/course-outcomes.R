# course-outcomes.R — Course Outcome and Persistence Analysis
#
# For a specific course (or set of courses), breaks down what happened to
# students after each grade outcome: did they return next term? How has the
# DFW rate changed over time? How do instructors compare to the course average?
#
# "Returned next term" is the retention definition from
# branches/retention-context.R -- registered anywhere at UNM in the next fall or
# spring, or graduated in between -- computed by the same .compute_retention(),
# so the persistence table and Course Dynamics' retention trend cannot disagree
# (ISSUES.md I17).
#
# This is course-first analysis. For cohort-first stop-out analysis (which
# courses are bleeding a specific student population?), see stopout.R.
#
# The outcome analyses take cedar_attempts (ADR-001 step 7); the persistence
# analyses take cedar_registrations, whose next-term rows they still read.
#
# DFW calculations delegate to get_course_outcome_rates() so cones use the
# shared course-attempt/outcome contract.
#
# Depends on: STATUS_REGISTERED, STATUS_DROP_EARLY (lists/status_codes.R)
#             GRADES_DFW, GRADES_PASS (lists/grades.R)
#             get_course_outcome_rates() (branches/course-attempts.R)
#             .resolve_retention_context(), .compute_retention()
#               (branches/retention-context.R)
#             classify_enrollment_outcomes(), dedup_enrollment() (trunk/utils.R)


# ── Main wrapper ──────────────────────────────────────────────────────────────

#' Analyze outcomes for one or more courses
#'
#' Runs the DFW trend and instructor comparison and returns them as a named
#' list. Next-term persistence needs degrees and is computed separately by
#' get_course_persistence().
#'
#' DFW trend and instructor comparison delegate to get_course_outcome_rates()
#' so the DFW formula and component fields match the rest of the app.
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param cedar_faculty cedar_faculty data frame; kept for the callers, unread here.
#' @param opt Options list:
#'   \itemize{
#'     \item \code{course}  — character vector of subject_course values (required)
#'     \item \code{term}    — integer vector; restrict to these terms (optional)
#'     \item \code{campus}  — character vector; restrict by campus (optional)
#'     \item \code{min_n}   — integer; minimum graded students per group (default 5)
#'     \item \code{data_edges} — output of [cedar_data_edges()]; longitudinal
#'       grade outputs stop at the earlier of the complete-enrollment and graded
#'       edges, while persistence eligibility uses the complete-enrollment edge
#'   }
#' @return Named list:
#'   \describe{
#'     \item{dfw_trend}{Tibble: campus, college, subject_course, term, dfw_pct}
#'     \item{instructor_dfw}{Tibble: campus, college, subject_course, instructor_id, instructor_name,
#'       dfw_pct, course_avg_dfw, dfw_diff}
#'     \item{courses}{Character vector of courses analyzed}
#'   }
get_course_outcomes <- function(attempts, cedar_faculty = NULL, opt = list()) {

  message("[course-outcomes.R] Welcome to get_course_outcomes!")

  courses <- opt$course %||% opt$courses
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-outcomes.R] opt$course is required.")
  }
  courses <- as.character(courses)
  message("[course-outcomes.R] Courses: ", paste(courses, collapse = ", "))

  # The longitudinal edge: the earlier of the settled and graded edges, so a
  # term whose enrollment is still open never enters the trend.
  analysis_end <- cedar_longitudinal_edge(opt$data_edges, grade_dependent = TRUE)
  outcome_attempts <- attempts
  if (!is.null(analysis_end)) {
    outcome_attempts <- dplyr::filter(outcome_attempts, term <= .env$analysis_end)
  }

  # The attempts in scope, to report what was found; the rates below read the
  # same scope through get_course_outcome_rates().
  filtered <- prepare_course_attempts(outcome_attempts, opt)

  if (nrow(filtered) == 0) {
    message("[course-outcomes.R] No records after filtering.")
    return(list(
      dfw_trend      = tibble(),
      instructor_dfw = tibble(),
      courses        = courses
    ))
  }

  message("[course-outcomes.R] ", n_distinct(filtered$student_id),
          " students across ", n_distinct(filtered$term), " terms.")

  # ── DFW analyses via shared course outcome rates ────────────────────────────

  dfw_trend_out      <- tibble()
  instructor_dfw_out <- tibble()
  min_n <- opt$min_n %||% 1L

  dfw_trend_out <- get_course_outcome_rates(
    outcome_attempts, opt,
    group_cols = c("campus", "college", "subject_course", "term"),
    min_n = min_n
  )
  message("[course-outcomes.R] DFW trend: ", nrow(dfw_trend_out), " term rows.")

  ci <- get_course_outcome_rates(
    outcome_attempts, opt,
    group_cols = c("campus", "college", "subject_course", "instructor_id", "instructor_name"),
    min_n = min_n
  )
  ca <- get_course_outcome_rates(
    outcome_attempts, opt,
    group_cols = c("campus", "college", "subject_course"),
    min_n = 1L
  )

  if (!is.null(ci) && nrow(ci) > 0 && !is.null(ca) && nrow(ca) > 0) {
    instructor_dfw_out <- ci %>%
      left_join(
        ca %>% select(campus, college, subject_course, course_avg_dfw = dfw_pct),
        by = c("campus", "college", "subject_course")
      ) %>%
      mutate(dfw_diff = round(dfw_pct - course_avg_dfw, 3)) %>%
      arrange(subject_course, dfw_diff)
    message("[course-outcomes.R] Instructor comparison: ", nrow(instructor_dfw_out), " rows.")
  }

  list(
    dfw_trend      = dfw_trend_out,
    instructor_dfw = instructor_dfw_out,
    courses        = courses
  )
}


# ── Persistence analysis ──────────────────────────────────────────────────────

#' Next-term persistence for one course, from cedar_registrations
#'
#' Selects the course's registered, early-drop, and late-drop rows in the
#' requested campus and term scope, keeps one row per student, course, and term,
#' and passes them to next_term_persistence(). This is what Course Dynamics ->
#' Retention shows beside the retention trend.
#'
#' @param students Full cedar_registrations table (also the UNM-wide return source).
#' @param degrees cedar_degrees; graduates count as returned.
#' @param opt `course` (required), optional `campus` and `term`, plus the
#'   next_term_persistence() options.
#' @param context Optional build_retention_context() output, shared with the
#'   retention trend so both read the same lookups.
#' @param student_terms `cedar_student_terms`, read for the `enrolled` lookup
#'   when no `context` is passed.
#' @return See next_term_persistence().
get_course_persistence <- function(students, degrees, opt = list(), context = NULL,
                                   student_terms = NULL) {
  courses <- opt$course
  if (is.null(courses) || length(courses) == 0 || !any(nzchar(courses))) {
    stop("[course-outcomes.R] get_course_persistence: opt$course is required.")
  }
  filtered <- students %>%
    filter(
      subject_course %in% .env$courses,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE)
    ) %>%
    cedar_filter_campus(opt$campus, fn = "get_course_persistence")
  if (length(opt$term) > 0) filtered <- filter(filtered, term %in% opt$term)
  filtered <- dedup_enrollment(filtered, level = "course")
  next_term_persistence(filtered, students, degrees, opt, context = context,
                        student_terms = student_terms)
}

#' Next-term persistence by grade outcome
#'
#' For each course outcome (pass, fail, late drop, early drop), how many
#' students returned the following fall or spring. Gives a course-level view of
#' whether bad outcomes go with leaving.
#'
#' "Returned" is the retention definition, computed by the same
#' .compute_retention() as the retention trend: enrolled anywhere at UNM in
#' the next regular term (cedar_student_terms' `enrolled`: registered, or
#' registered and withdrawn after census), or graduated between the course
#' term and that term. A next-term row that is only an early drop or a waitlist
#' is not a return, and a graduate has not left. Anchors whose next term is
#' beyond the observation edge are excluded, never counted as not returned.
#'
#' Outcomes come from classify_enrollment_outcomes(): its "dfw" outcomes are
#' split into "late drop" (a late-drop status or a W grade) and "fail"; early
#' drops (no grade, never DFW) are their own group.
#'
#' The unit is a student's course term: a student who took the course in two
#' terms counts once per term, as in the retention trend.
#'
#' @param filtered One row per student, course, and term (dedup_enrollment(level =
#'   "course")) for the target course(s): registered, early-drop, and late-drop
#'   rows.
#' @param all_students Full cedar_registrations table: the UNM-wide return source.
#' @param degrees cedar_degrees, for graduation.
#' @param opt `min_n` (default 5), `passing_grades` (default GRADES_PASS; the
#'   page's opt-in uses GRADES_PASS_SUB_C_OPT_IN), and `data_edges` or
#'   `observation_end_term`.
#' @param context Optional build_retention_context() output.
#' @param student_terms `cedar_student_terms`, read for the `enrolled` lookup
#'   when no `context` is passed.
#' @return Tibble: campus, subject_course, outcome, n_students, n_returned,
#'   pct_returned (a proportion, unrounded); sorted by campus, subject_course,
#'   outcome.
next_term_persistence <- function(filtered, all_students, degrees, opt = list(),
                                  context = NULL, student_terms = NULL) {
  min_n <- opt$min_n %||% 5L
  cedar_require_campus(filtered, "next_term_persistence")
  required <- c("student_id", "term", "campus", "subject_course",
                "registration_status_code", "final_grade")
  missing <- setdiff(required, names(filtered))
  if (length(missing)) {
    stop("[course-outcomes.R] next_term_persistence: missing columns: ",
         paste(missing, collapse = ", "))
  }
  if (is.null(degrees)) {
    stop("[course-outcomes.R] next_term_persistence: degrees are required; ",
         "without them every graduate reads as not returned.")
  }

  message("[course-outcomes.R] Computing next-term persistence by outcome...")
  context <- .resolve_retention_context(all_students, degrees, opt, context, student_terms)

  # The anchor outcome reads a grade, so a settled but partly graded term cannot
  # enter the cohort merely because its following term is observable.
  grade_end <- cedar_longitudinal_edge(opt$data_edges, grade_dependent = TRUE)
  if (!is.null(grade_end)) {
    filtered <- filter(filtered, term <= .env$grade_end)
  }

  early <- filtered %>%
    filter(registration_status_code %in% STATUS_DROP_EARLY) %>%
    mutate(outcome = "early drop")
  graded <- classify_enrollment_outcomes(filtered, opt$passing_grades %||% GRADES_PASS) %>%
    mutate(outcome = case_when(
      outcome == "pass" ~ "pass",
      registration_status_code %in% STATUS_DROP_LATE |
        trimws(final_grade) == "W" ~ "late drop",
      TRUE ~ "fail"
    ))

  cohort <- bind_rows(early, graded) %>%
    distinct(student_id, campus, subject_course, anchor_term = term, outcome)
  if (nrow(cohort) == 0) return(tibble())
  if (anyDuplicated(cohort[c("student_id", "campus", "subject_course", "anchor_term")])) {
    stop("[course-outcomes.R] next_term_persistence: a student has two outcomes for ",
         "one course term; deduplicate with dedup_enrollment(level = \"course\") first.")
  }

  # NA means the next regular term is beyond the observation edge: excluded.
  returned <- .compute_retention(cohort, context$enrolled_lookup, 1L,
                                 context$graduated_lookup) %>%
    filter(!is.na(retained_1))

  result <- returned %>%
    group_by(campus, subject_course, outcome) %>%
    summarize(
      n_students = n(),
      n_returned = sum(retained_1),
      .groups    = "drop"
    ) %>%
    mutate(pct_returned = n_returned / n_students) %>%
    filter(n_students >= min_n) %>%
    mutate(outcome = factor(outcome, levels = c("early drop", "late drop", "fail", "pass"))) %>%
    arrange(campus, subject_course, outcome) %>%
    mutate(outcome = as.character(outcome))

  message("[course-outcomes.R] Persistence table: ", nrow(result), " outcome groups.")
  result
}
