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

  # One pass over the class list decides every row, so it is copied once and
  # only in the columns the table keeps: the whole 34-column class list,
  # filtered then mutated and classified, peaked 1.5 GB above the loaded tables
  # on the 2026-10-08 pull, and the app's 3.8 GB container was killed at start.
  # Kept: registered, early-drop and late-drop rows to the graded edge, less
  # audits (an early drop is "Drop" whatever its grade, so it is never an
  # audit), the rows prepare_course_attempts() keeps.
  status <- students$registration_status_code
  raw_grade <- trimws(as.character(students$final_grade))
  keep <- as.integer(students$term) <= graded_edge &
    status %in% c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE) &
    !(!status %in% STATUS_DROP_EARLY & raw_grade %in% GRADES_EXCLUDED_FROM_OUTCOMES)
  keep[is.na(keep)] <- FALSE
  source_cols <- setdiff(ATTEMPTS_COLUMNS, c("outcome_category", "outcome"))
  rows <- dplyr::ungroup(students)[keep, source_cols]
  raw_grade <- dplyr::na_if(raw_grade[keep], "")
  rm(status, keep)
  n_keys <- nrow(dplyr::distinct(rows, student_id, term, campus, subject_course))
  if (n_keys != nrow(rows)) {
    dup <- rows[duplicated(rows[c("student_id", "term", "campus", "subject_course")]), ]
    stop("[attempts.R] build_attempts(): ", nrow(rows) - n_keys, " student-course-campus-terms ",
         "hold more than one class-list row (first: ", dup$student_id[1], " ",
         dup$subject_course[1], " ", dup$term[1], "); the loaded class list should hold one")
  }

  # The grade as prepare_course_attempts() reads it: an early drop is "Drop",
  # and a late drop with no grade posted is "W".
  rows$final_grade <- dplyr::case_when(
    rows$registration_status_code %in% STATUS_DROP_EARLY ~ "Drop",
    rows$registration_status_code %in% STATUS_DROP_LATE & is.na(raw_grade) ~ "W",
    TRUE ~ raw_grade)
  rm(raw_grade)

  # Classified a term at a time on the two columns the classifier reads, with
  # the garbage collected between terms: at once, its flag columns and their
  # temporaries peaked near 1 GB, and R collects against a ~3 GB live heap
  # only late. The category and outcome come from the classifier's own flags,
  # so they cannot drift from it.
  gc(verbose = FALSE)
  category <- outcome <- rep(NA_character_, nrow(rows))
  for (i in split(seq_len(nrow(rows)), rows$term)) {
    classified <- classify_attempt_outcomes(rows[i, c("registration_status_code", "final_grade")])
    category[i] <- classified$outcome_category
    outcome[i] <- dplyr::case_when(classified$is_pass ~ "pass",
                                   classified$is_dfw_legacy ~ "dfw",
                                   TRUE ~ NA_character_)
    rm(classified)
    gc(verbose = FALSE)
  }
  if (any(category == "other")) {
    stop("[attempts.R] build_attempts(): ", sum(category == "other"),
         " attempts fell through every outcome category")
  }
  rows$outcome_category <- category
  rows$outcome <- outcome
  out <- rows[, ATTEMPTS_COLUMNS]

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
