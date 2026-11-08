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
#' @param students The loaded cedar_registrations, keyed on the course
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

  # Built a term at a time. Every key holds the term, so each term's rows are
  # decided, checked and classified alone, and the class list is never copied
  # whole: over the whole 34-column class list at once the build peaked 1.5 GB
  # above the loaded tables, and in the app's 3.8 GiB container even a
  # 12-column copy with the garbage collected between steps reached 3.5 GiB
  # and was killed at start (2026-11-07). Per term, the peak is the pieces and
  # the bound table.
  # Kept: registered, early-drop and late-drop rows to the graded edge, less
  # audits (an early drop is "Drop" whatever its grade, so it is never an
  # audit), the rows prepare_course_attempts() keeps.
  term <- as.integer(students$term)
  candidates <- which(term <= graded_edge &
                        students$registration_status_code %in%
                          c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE))
  by_term <- split(candidates, term[candidates])
  rm(term, candidates)
  source_cols <- setdiff(ATTEMPTS_COLUMNS, c("outcome_category", "outcome"))
  students <- dplyr::ungroup(students)
  pieces <- lapply(by_term, function(i) .attempts_for_rows(students[i, source_cols]))
  rm(by_term)
  out <- if (length(pieces)) {
    dplyr::bind_rows(pieces)[, ATTEMPTS_COLUMNS]
  } else {
    # No graded attempt at all: the empty table, with every column.
    dplyr::mutate(students[0, source_cols], outcome_category = character(),
                  outcome = character())[, ATTEMPTS_COLUMNS]
  }
  rm(pieces)

  attr(out, "attempts_build_version") <- ATTEMPTS_BUILD_VERSION
  attr(out, "cedar_outcome_policy_version") <- CEDAR_OUTCOME_POLICY_VERSION
  attr(out, "graded_edge") <- graded_edge
  attr(out, "code_renames") <- course_code_renames(students)
  out
}


# One term's class-list rows (registered and dropped, to the graded edge) as
# attempts: audits out, the grade as prepare_course_attempts() reads it, one
# row per student, course and campus, classified by classify_attempt_outcomes()
# with the outcome taken from its own flags, so it cannot drift from it.
.attempts_for_rows <- function(rows) {
  status <- rows$registration_status_code
  grade <- dplyr::na_if(trimws(as.character(rows$final_grade)), "")
  audit <- !status %in% STATUS_DROP_EARLY & grade %in% GRADES_EXCLUDED_FROM_OUTCOMES
  rows <- rows[!audit, ]
  status <- status[!audit]
  grade <- grade[!audit]
  dup <- duplicated(rows[c("student_id", "campus", "subject_course")])
  if (any(dup)) {
    stop("[attempts.R] build_attempts(): ", sum(dup), " student-course-campus-terms in ",
         rows$term[1], " hold more than one class-list row (first: ",
         rows$student_id[dup][1], " ", rows$subject_course[dup][1],
         "); the loaded class list should hold one")
  }
  # An early drop is "Drop"; a late drop with no grade posted is "W".
  rows$final_grade <- dplyr::case_when(
    status %in% STATUS_DROP_EARLY ~ "Drop",
    status %in% STATUS_DROP_LATE & is.na(grade) ~ "W",
    TRUE ~ grade)
  classified <- classify_attempt_outcomes(rows[c("registration_status_code", "final_grade")])
  if (any(classified$outcome_category == "other")) {
    stop("[attempts.R] build_attempts(): ", sum(classified$outcome_category == "other"),
         " attempts in ", rows$term[1], " fell through every outcome category")
  }
  rows$outcome_category <- classified$outcome_category
  rows$outcome <- dplyr::case_when(classified$is_pass ~ "pass",
                                   classified$is_dfw_legacy ~ "dfw",
                                   TRUE ~ NA_character_)
  rows
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


#' Refuse an attempts table this build did not make
#'
#' For a reader handed `attempts` without the class list it came from (a cone
#' given a population-windowed copy): checks the build, outcome policy and
#' columns, which survive filtering, and returns the graded edge it was built
#' to. The loader checks the course codes (attempts_is_current()).
require_attempts_build <- function(attempts, caller) {
  ok <- is.data.frame(attempts) &&
    identical(attr(attempts, "attempts_build_version", exact = TRUE), ATTEMPTS_BUILD_VERSION) &&
    identical(attr(attempts, "cedar_outcome_policy_version", exact = TRUE),
              CEDAR_OUTCOME_POLICY_VERSION) &&
    identical(names(attempts), ATTEMPTS_COLUMNS)
  if (!ok) {
    stop("[attempts.R] ", caller, ": attempts was not built by build_attempts() under this ",
         "build and outcome policy (build, outcome policy or columns differ); rebuild it with ",
         "build_attempts()")
  }
  invisible(attr(attempts, "graded_edge", exact = TRUE))
}


#' Refuse an attempts table this code did not build, or built over other codes
#'
#' For readers handed `attempts` with the class list but not the edges: checks
#' the build, policy, columns and renames, and returns the graded edge it was
#' built to.
require_current_attempts <- function(attempts, students, caller) {
  graded_edge <- require_attempts_build(attempts, caller)
  if (!identical(attr(attempts, "code_renames", exact = TRUE), course_code_renames(students))) {
    stop("[attempts.R] ", caller, ": attempts was not built by build_attempts() from this ",
         "class list (its course codes differ); rebuild it with build_attempts()")
  }
  invisible(graded_edge)
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
