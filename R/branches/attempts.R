# cedar_attempts: one classified outcome per graded course attempt
# (ADR-001 step 4, the attempt measure table).
#
# The grain is the loaded class list's: one row per student, course, campus
# and term. The class list is keyed on the course at load, so a renumbered
# course's attempts are one course's, and the transform already collapsed a
# combined course's lecture and lab rows into one. Every attempt is classified
# once, here, by classify_attempt_outcomes() (R/branches/course-attempts.R),
# so every reader shares one answer to "did this attempt pass, fail or
# withdraw?" instead of reclassifying the class list per request.
#
# Which rows are attempts: the same rows prepare_course_attempts() keeps from
# the class list. Registered, early-dropped and late-dropped rows, audits
# excluded, in terms up to the graded edge. A term after the edge has no
# outcomes yet: its rows are unknown, never failures, so they are left out
# (the right-edge policy). An early drop is an attempt row with no outcome; it
# is never DFW and never in a DFW denominator.
#
# `outcome` is the default policy (definition: dfw): "pass" for A+ through C
# and CR, "dfw" for every other recorded grade and for late withdrawals, NA for
# early drops and for registered rows with no grade. `outcome_category` keeps
# the finer category (pass, c_minus, d, f, other_nonpassing,
# w_late_withdrawal, early_drop, missing), so a page with the visible C-/D
# opt-in can count c_minus and d as passing without reclassifying.
#
# Like cedar_course_terms, it is built at load, held in data_objects and passed
# to readers as a parameter; a copy saved beside the data is a cache, checked
# by attempts_is_current() before it is used.

# Bump when a column or the row rule changes, so a cached copy is rebuilt.
ATTEMPTS_BUILD_VERSION <- 1L

ATTEMPTS_COLUMNS <- c(
  "student_id", "term", "campus", "college", "part_term", "subject_course",
  "listed_code", "level", "department", "crn", "registration_status_code",
  "final_grade", "outcome_category", "outcome"
)

#' Build cedar_attempts from the loaded class list
#'
#' @param students The loaded cedar_students, keyed on the course
#'   (attach_course_ids()), one row per student, course, campus and term.
#' @param edges The startup edges (cedar_report_edges()$edges);
#'   `last_graded` bounds the table and fails closed when unknown.
#' @return A tibble with ATTEMPTS_COLUMNS, stamped with
#'   `attempts_build_version`, `cedar_outcome_policy_version`, `graded_edge`
#'   and the class list's `code_renames`.
build_attempts <- function(students, edges) {
  .listed_codes(students, "build_attempts")
  missing <- setdiff(setdiff(ATTEMPTS_COLUMNS, c("outcome_category", "outcome")), names(students))
  if (length(missing)) {
    stop("[attempts.R] build_attempts(): students lacks ", paste(missing, collapse = ", "))
  }
  graded_edge <- edges$last_graded
  if (is.null(graded_edge) || length(graded_edge) != 1L || is.na(graded_edge)) {
    stop("[attempts.R] build_attempts(): edges$last_graded is undetermined; refusing to ",
         "classify outcomes without a graded edge.")
  }
  graded_edge <- as.integer(graded_edge)

  rows <- students %>%
    dplyr::ungroup() %>%
    dplyr::filter(as.integer(term) <= graded_edge,
                  registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_EARLY,
                                                  STATUS_DROP_LATE))
  dup <- rows %>% dplyr::count(student_id, term, campus, subject_course) %>% dplyr::filter(n > 1L)
  if (nrow(dup)) {
    stop("[attempts.R] build_attempts(): ", nrow(dup), " student-course-campus-terms hold more ",
         "than one class-list row (first: ", dup$student_id[1], " ", dup$subject_course[1], " ",
         dup$term[1], "); the loaded class list should hold one")
  }

  # The grade as prepare_course_attempts() reads it: an early drop is "Drop",
  # a late drop with no grade posted is "W", and audits are not attempts.
  rows <- rows %>%
    dplyr::mutate(
      .raw = dplyr::na_if(trimws(as.character(final_grade)), ""),
      final_grade = dplyr::case_when(
        registration_status_code %in% STATUS_DROP_EARLY ~ "Drop",
        registration_status_code %in% STATUS_DROP_LATE & is.na(.raw) ~ "W",
        TRUE ~ .raw)) %>%
    dplyr::select(-.raw) %>%
    dplyr::filter(!final_grade %in% GRADES_EXCLUDED_FROM_OUTCOMES)

  classified <- classify_attempt_outcomes(rows)
  if (any(classified$outcome_category == "other")) {
    stop("[attempts.R] build_attempts(): ", sum(classified$outcome_category == "other"),
         " attempts fell through every outcome category")
  }
  # The classifier's own flags, so the outcome cannot drift from it.
  out <- classified %>%
    dplyr::mutate(outcome = dplyr::case_when(
      is_pass ~ "pass",
      is_dfw_legacy ~ "dfw",
      TRUE ~ NA_character_)) %>%
    dplyr::select(dplyr::all_of(ATTEMPTS_COLUMNS))

  attr(out, "attempts_build_version") <- ATTEMPTS_BUILD_VERSION
  attr(out, "cedar_outcome_policy_version") <- CEDAR_OUTCOME_POLICY_VERSION
  attr(out, "graded_edge") <- graded_edge
  attr(out, "code_renames") <- course_code_renames(students)
  out
}


#' Whether an attempts table was built by this code from this class list and edge
#'
#' @return TRUE only for a data frame with this build's version, outcome
#'   policy, columns and graded edge, counted over the class list's renames.
attempts_is_current <- function(attempts, students, edges) {
  is.data.frame(attempts) &&
    identical(attr(attempts, "attempts_build_version", exact = TRUE), ATTEMPTS_BUILD_VERSION) &&
    identical(attr(attempts, "cedar_outcome_policy_version", exact = TRUE),
              CEDAR_OUTCOME_POLICY_VERSION) &&
    identical(names(attempts), ATTEMPTS_COLUMNS) &&
    identical(attr(attempts, "graded_edge", exact = TRUE), as.integer(edges$last_graded)) &&
    identical(attr(attempts, "code_renames", exact = TRUE), course_code_renames(students))
}


#' Refuse an attempts table this code did not build, or built over other codes
#'
#' For readers handed `attempts` with the class list but not the edges: checks
#' the build, policy, columns and renames, and returns the graded edge it was
#' built to.
require_current_attempts <- function(attempts, students, caller) {
  ok <- is.data.frame(attempts) &&
    identical(attr(attempts, "attempts_build_version", exact = TRUE), ATTEMPTS_BUILD_VERSION) &&
    identical(attr(attempts, "cedar_outcome_policy_version", exact = TRUE),
              CEDAR_OUTCOME_POLICY_VERSION) &&
    identical(names(attempts), ATTEMPTS_COLUMNS) &&
    identical(attr(attempts, "code_renames", exact = TRUE), course_code_renames(students))
  if (!ok) {
    stop("[attempts.R] ", caller, ": attempts was not built by build_attempts() from this ",
         "class list (build, outcome policy, columns or course codes differ); rebuild it with ",
         "build_attempts()")
  }
  invisible(attr(attempts, "graded_edge", exact = TRUE))
}


#' Outcome counts per course term, at the course-terms grain
#'
#' @param attempts A current cedar_attempts.
#' @return One row per campus, college, term, course and part of term with any
#'   attempt: `attempts` (passed + dfw: the DFW denominator), `passed`, `dfw`,
#'   and `withdrawn` (late withdrawals, a part of dfw).
count_attempt_outcomes <- function(attempts) {
  attempts %>%
    dplyr::group_by(campus, college, term, subject_course, part_term) %>%
    dplyr::summarize(
      attempts  = sum(!is.na(outcome)),
      passed    = sum(outcome %in% "pass"),
      dfw       = sum(outcome %in% "dfw"),
      withdrawn = sum(outcome_category == "w_late_withdrawal"),
      .groups = "drop")
}
