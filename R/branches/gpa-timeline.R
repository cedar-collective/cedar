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
# The transform sums them once per student-term onto cedar_student_terms
# (`quality_points`, `graded_hours`, and their running totals; ADR-001 step 7
# group 4), and a credit-weighted running mean over them is a cumulative GPA
# that moves:
#
#   gpa_after    = cumulative_quality_points / cumulative_graded_hours, through term T
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
#   * Only grades that carry points count (CEDAR_GRADE_POINTS, R/lists/grades.R).
#     CR/NC, W, I, PR, AUD and the R-prefixed variants are excluded from both
#     the numerator and the hours denominator, which is what Banner does too.
#   * Left truncation applies exactly as it does to credits: a student already
#     enrolled when the window opens has their running mean start mid-career on
#     partial data. The table's `timeline_valid` marks them and callers must
#     filter.
#   * Posted grades only, as `dfw_grades` is: a term past the graded edge has
#     few or none, so a reader claiming a cumulative GPA *at* a term bounds its
#     terms at `last_graded`. `gpa_entering` at a term reads only earlier terms.


#' Build a Per-Term Cumulative GPA for Students
#'
#' One row per (student, term in which they earned graded hours) giving the
#' credit-weighted cumulative GPA entering and after that term, read off
#' `cedar_student_terms`' grade-point columns.
#'
#' @param student_terms `cedar_student_terms` (build_student_terms()). Needs
#'   `student_id`, `term`, `quality_points`, `graded_hours`,
#'   `cumulative_quality_points`, `cumulative_graded_hours` and `timeline_valid`.
#' @param opt List of options:
#'   \describe{
#'     \item{`student_ids`}{Character vector. Restrict to these students.}
#'   }
#'   The window options the class-list series took (`min_data_term`,
#'   `student_first_terms`) are refused: the table sets `timeline_valid` over
#'   the whole data, and a slice of it keeps the right answer.
#'
#' @return Tibble with `student_id`, `term`, `term_gpa`, `graded_hours`,
#'   `gpa_entering`, `gpa_after`, `graded_hours_entering` and `timeline_valid`.
#'   `gpa_entering` is NA in a student's first graded term — there is no prior
#'   record to average, and 0.0 would be a failing student rather than an unknown
#'   one.
build_gpa_timeline <- function(student_terms, opt = list()) {

  needed <- c("student_id", "term", "quality_points", "graded_hours",
              "cumulative_quality_points", "cumulative_graded_hours", "timeline_valid")
  missing_cols <- setdiff(needed, names(student_terms))
  if (length(missing_cols) > 0) {
    stop("[gpa-timeline.R] student_terms is missing required column(s): ",
         paste(missing_cols, collapse = ", "),
         ". Expected cedar_student_terms as build_student_terms() writes it (build ",
         STUDENT_TERMS_BUILD_VERSION, " or later).")
  }
  refused <- intersect(c("min_data_term", "student_first_terms"), names(opt))
  if (length(refused) > 0) {
    stop("[gpa-timeline.R] build_gpa_timeline() reads timeline_valid off cedar_student_terms; ",
         "opt$", paste(refused, collapse = ", opt$"), " is not an option it answers.")
  }

  st <- dplyr::ungroup(student_terms)
  if (!is.null(opt$student_ids) && length(opt$student_ids) > 0) {
    st <- dplyr::filter(st, student_id %in% opt$student_ids)
  }

  st %>%
    dplyr::filter(graded_hours > 0) %>%
    dplyr::transmute(
      student_id,
      term = as.integer(term),
      term_gpa = quality_points / graded_hours,
      graded_hours,
      graded_hours_entering = cumulative_graded_hours - graded_hours,
      # No prior graded hours means no prior record. NA, not 0 — a 0.0 here would
      # be read as a failing student and would drag every group mean it enters.
      gpa_entering = dplyr::if_else(
        graded_hours_entering > 0,
        (cumulative_quality_points - quality_points) / graded_hours_entering,
        NA_real_
      ),
      gpa_after = cumulative_quality_points / cumulative_graded_hours,
      timeline_valid = dplyr::coalesce(timeline_valid, FALSE)
    ) %>%
    dplyr::select(student_id, term, term_gpa, graded_hours,
                  gpa_entering, gpa_after, graded_hours_entering, timeline_valid) %>%
    dplyr::arrange(student_id, term)
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
