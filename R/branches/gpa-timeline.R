# gpa-timeline.R — a cumulative GPA that actually moves
#
# THE PROBLEM
#
# `inst_gpa` on cedar_programs is Banner's "Institution GPA", stamped as of the
# data pull onto every historical row it returns. Measured on current data it is
# identical across every term of a student's own history for 67.8% of students
# with 5+ terms. It is not a GPA "at term T"; it is the student's GPA today,
# printed once per term.
#
# That makes it unusable as a matching covariate. A comparison that matches
# treatment and control on `inst_gpa` is matching on where each student ended up
# — which, for any outcome measured after the covariate term, is partly the
# outcome itself. The balance table then reports good balance on a variable that
# was never measured at the point of comparison.
#
# THE RECONSTRUCTION
#
# Grade points are on the class list, one row per course taken, and that series
# is per-term and pull-stable (see the field reliability contract in AGENTS.md).
# A credit-weighted running mean over it is a cumulative GPA that moves:
#
#   gpa_after    = sum(grade_points * credits) / sum(credits), through term T
#   gpa_entering = the same, through the term BEFORE T
#
# `gpa_entering` is the one to match on. It answers "what did this student's
# record look like walking into the term where the comparison happens", and it
# cannot contain the term's own grade — which, for a course-effect study, is the
# outcome.
#
# VALIDATED against the frozen field at the one point the frozen field is right.
# `inst_gpa` is stamped at pull, so it should equal a student's true cumulative
# GPA at the END of their record and nowhere else. For students whose whole
# history is inside the window, the reconstruction lands within a median of
# **0.090** of it (85% within 0.25, 95% within 0.50, r = 0.937). It converges
# where it must and diverges where the frozen field is wrong.
#
# WHAT THIS IS NOT
#
#   * Not Banner's official GPA. UNM's repeat policy replaces the earlier grade
#     of a repeated course in the official calculation; this counts both
#     attempts. Students who repeat a lot read slightly low here.
#   * UNM coursework only. Transfer GPA is a separate field and is not folded in.
#   * Only grades that carry points count. CR/NC, W, I, PR, AUD and the R-prefixed
#     variants are excluded from both the numerator and the hours denominator,
#     which is what Banner does too.
#   * Left truncation applies exactly as it does to credits: a student already
#     enrolled when the window opens has their running mean start mid-career on
#     partial data. `timeline_valid` marks them and callers must filter.


# Grade points for UNM letter grades. Anything not named here carries no points
# and no graded hours — the two must be dropped together or the denominator
# silently inflates and every affected student reads low.
CEDAR_GRADE_POINTS <- c(
  "A+" = 4.0, "A" = 4.0, "A-" = 3.7,
  "B+" = 3.3, "B" = 3.0, "B-" = 2.7,
  "C+" = 2.3, "C" = 2.0, "C-" = 1.7,
  "D+" = 1.3, "D" = 1.0, "D-" = 0.7,
  "F"  = 0.0
)


#' Build a Per-Term Cumulative GPA for Students
#'
#' One row per (student, term in which they earned graded hours) giving the
#' credit-weighted cumulative GPA entering and after that term.
#'
#' @param students Data frame. `cedar_students`. Needs `student_id`, `term`,
#'   `final_grade` and `credits`.
#' @param opt List of options:
#'   \describe{
#'     \item{`student_ids`}{Character vector. Restrict to these students.
#'       Strongly recommended — the full class list is large.}
#'     \item{`min_data_term`}{Integer. First term present in the data, used to
#'       set `timeline_valid`. Defaults to the earliest term in `students`.}
#'     \item{`student_first_terms`}{Data frame of `student_id` / `first_unm_term`.
#'       **Required if you pre-filtered `students` by term** — see
#'       [credit_timeline_validity()], which this shares.}
#'   }
#'
#' @return Tibble with `student_id`, `term`, `term_gpa`, `graded_hours`,
#'   `gpa_entering`, `gpa_after`, `graded_hours_entering` and `timeline_valid`.
#'   `gpa_entering` is NA in a student's first graded term — there is no prior
#'   record to average, and 0.0 would be a failing student rather than an unknown
#'   one.
build_gpa_timeline <- function(students, opt = list()) {

  needed <- c("student_id", "term", "final_grade", "credits")
  missing_cols <- setdiff(needed, names(students))
  if (length(missing_cols) > 0) {
    stop("[gpa-timeline.R] students is missing required column(s): ",
         paste(missing_cols, collapse = ", "),
         ". Expected the cedar_students table.")
  }

  st <- students
  if (!is.null(opt$student_ids) && length(opt$student_ids) > 0) {
    st <- dplyr::filter(st, student_id %in% opt$student_ids)
  }

  graded <- st %>%
    dplyr::filter(
      final_grade %in% names(CEDAR_GRADE_POINTS),
      !is.na(credits), credits > 0, !is.na(term)
    )

  if (nrow(graded) == 0) {
    return(tibble::tibble(
      student_id = character(), term = integer(),
      term_gpa = numeric(), graded_hours = numeric(),
      gpa_entering = numeric(), gpa_after = numeric(),
      graded_hours_entering = numeric(), timeline_valid = logical()
    ))
  }

  timeline <- graded %>%
    dplyr::mutate(quality_points = unname(CEDAR_GRADE_POINTS[final_grade]) * credits) %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(
      quality_points = sum(quality_points),
      graded_hours   = sum(credits),
      .groups = "drop"
    ) %>%
    dplyr::arrange(student_id, term) %>%
    dplyr::group_by(student_id) %>%
    dplyr::mutate(
      cum_points_after = cumsum(quality_points),
      cum_hours_after  = cumsum(graded_hours),
      # Entering = through the prior term. cumsum() minus this term is the same
      # thing and avoids a lag() that would need a first-row special case.
      cum_points_entering = cum_points_after - quality_points,
      graded_hours_entering = cum_hours_after - graded_hours,
      term_gpa     = quality_points / graded_hours,
      gpa_after    = cum_points_after / cum_hours_after,
      # No prior graded hours means no prior record. NA, not 0 — a 0.0 here would
      # be read as a failing student and would drag every group mean it enters.
      gpa_entering = dplyr::if_else(graded_hours_entering > 0,
                                    cum_points_entering / graded_hours_entering,
                                    NA_real_)
    ) %>%
    dplyr::ungroup()

  # Same rule, same helper as the credit timeline: a running mean over a record
  # that starts mid-career is not a cumulative GPA, it is the GPA of whatever
  # fragment happens to be inside the window.
  validity <- credit_timeline_validity(students, opt = opt)

  timeline %>%
    dplyr::left_join(validity, by = "student_id") %>%
    dplyr::mutate(timeline_valid = dplyr::coalesce(timeline_valid, FALSE)) %>%
    dplyr::select(student_id, term, term_gpa, graded_hours,
                  gpa_entering, gpa_after, graded_hours_entering, timeline_valid)
}


#' Attach Cumulative GPA to an Event Table
#'
#' Joins `gpa_entering` onto rows keyed by student and term, taking the most
#' recent graded term at or before the event term — a student with no graded
#' hours in the event term itself still has a record walking into it.
#'
#' @param events Data frame with `student_id` and a term column.
#' @param gpa_timeline Output of [build_gpa_timeline()].
#' @param term_col Character. Name of the term column in `events`.
#' @return `events` with `gpa_entering` and `timeline_valid` added. Both are NA /
#'   FALSE where no usable prior record exists.
attach_gpa_position <- function(events, gpa_timeline, term_col = "term") {
  if (is.null(gpa_timeline) || nrow(gpa_timeline) == 0) {
    events$gpa_entering   <- NA_real_
    events$timeline_valid <- FALSE
    return(events)
  }

  # As-of join by hand: for each event, the latest timeline row at or before it.
  # A plain (student_id, term) join would drop any event term in which the
  # student earned no graded hours, which is exactly the population — withdrawals
  # and pass/fail-only terms — that a comparison should still be able to place.
  #
  # The match is computed on a row id and joined back, rather than filtered in
  # place. Filtering in place drops any event that precedes the student's first
  # graded term (every candidate row fails the <= test, so the event vanishes),
  # and grouping by the event's own columns to pick a winner would silently
  # collapse two identical event rows into one. Both are row-count bugs in a
  # function whose contract is that it returns exactly the rows it was given.
  keyed <- events %>%
    dplyr::mutate(.row_id = dplyr::row_number(), .event_term = .data[[term_col]])

  matched <- keyed %>%
    dplyr::select(.row_id, student_id, .event_term) %>%
    dplyr::left_join(
      gpa_timeline %>%
        dplyr::select(student_id, .tl_term = term, gpa_entering, timeline_valid),
      by = "student_id", relationship = "many-to-many"
    ) %>%
    dplyr::filter(!is.na(.tl_term), .tl_term <= .event_term) %>%
    dplyr::group_by(.row_id) %>%
    dplyr::slice_max(.tl_term, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(.row_id, gpa_entering, timeline_valid)

  keyed %>%
    dplyr::select(-.event_term) %>%
    dplyr::left_join(matched, by = ".row_id") %>%
    dplyr::mutate(timeline_valid = dplyr::coalesce(timeline_valid, FALSE)) %>%
    dplyr::select(-.row_id)
}
