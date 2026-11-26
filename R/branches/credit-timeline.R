# credit-timeline.R — where a student actually was, term by term
#
# The single sanctioned source for "how far into their studies was this student
# when X happened". Read the field reliability contract in AGENTS.md first; this
# file exists because of it.
#
# THE PROBLEM THIS SOLVES
#
# Academic Studies reports cumulative credit totals as of the moment you pull,
# stamped onto every historical row it returns. Within one full historical
# re-pull, `overall_credits_earned` moves across a student's own terms just 16%
# of the time, while the per-term columns move 98% of the time. A student's
# freshman row can read 129 earned credits. Any analysis that reads a cumulative
# column at a historical term is reading that student's total today, and no pull
# schedule fixes it — re-pulling produces the same freeze at a later date.
#
# THE RECONSTRUCTION
#
# UNM-side history is trustworthy: cedar_student_terms carries, on every
# student-term row, the term's attempted credits from the class list and the
# running total over the student's terms in the data (`unm_credits_entering`,
# `cumulative_attempted_unm_credits`), computed once in the transform by
# build_student_terms(). What it cannot see is credit the student arrived with.
#
# Transfer credit is recoverable as a difference of the two frozen columns. Both
# are stamped at the same instant, so the *gap* between them survives the freeze:
#   transfer = overall_credits_attempted - inst_credits_attempted
# measured on the same attempted basis, and stable across a student's rows 93% of
# the time. Adding that block to the UNM running total gives a per-term position
# that includes transfer credit.
#
# WHAT THIS IS STILL NOT
#
#   * The transfer block is as of the pull. Credit transferred in mid-career is
#     attributed to the student's start. Most transfer credit arrives at
#     admission, so this is usually right, but it is an assumption, not a fact.
#   * Attempted, not earned, unless asked. The default position counts every
#     credit attempted, here and elsewhere: the right figure for the attempted
#     -credit ceiling, the wrong one to set against a degree's credits or a
#     classification (ISSUES I91: on it 27% of one fall's juniors read 90 or
#     more). `opt$earned = TRUE` adds the earned position beside it: credits
#     completed here (passing grades) plus the earned block,
#     overall_credits_earned - inst_credits_earned, recovered the same way
#     and as stable (measured 2026-11-26: one gap on every row for 90.9% of
#     students, 91.1% for the attempted pair). The earned block is the
#     smaller for 29% of students (credit attempted elsewhere and not
#     earned) and the larger for 2% (credit granted without an attempt).
#   * The UNM running total starts at zero on the first term IN THE DATA. For a
#     student already enrolled when the window opens, their timeline begins
#     mid-career reading zero. `timeline_valid` marks who this applies to;
#     callers must filter or caveat rather than quietly averaging them in. The
#     flag is set on the table at build time, over the whole data, so a slice
#     of the table handed to this function keeps the right answer.


#' Build a Per-Term Credit Position for Students
#'
#' One row per student-term giving how many credits the student had *entering*
#' that term — the figure that answers "where were they when they did this" —
#' and after completing it. A term the student was declared but not enrolled in
#' is a row too, carrying the position unchanged.
#'
#' @param student_terms Data frame. `cedar_student_terms`. Required; this is
#'   the trustworthy UNM series, and `timeline_valid` is read from it.
#' @param programs Data frame or NULL. `cedar_programs`, used only to recover
#'   each student's transfer block. NULL yields a UNM-only timeline with
#'   `transfer_credits = 0` and `total_*` equal to `unm_*`, which is honest but
#'   understates anyone who arrived with credit.
#' @param opt List of options:
#'   \describe{
#'     \item{`student_ids`}{Character vector. Restrict to these students. Strongly
#'       recommended — the full table is ~520k rows.}
#'     \item{`earned`}{Logical, default FALSE. TRUE adds the earned position
#'       (below), and then needs `completed_unm_credits` and
#'       `cumulative_completed_unm_credits` on `student_terms` and
#'       `inst_credits_earned` and `overall_credits_earned` on `programs`.}
#'   }
#'
#' @return Tibble with `student_id`, `term`, `unm_credits_entering`,
#'   `unm_credits_after`, `transfer_credits`, `transfer_credits_known` (FALSE
#'   when the student has no recorded pair of totals to take the difference
#'   of: `transfer_credits` is then 0 and means "not recorded", which a new
#'   student's first pull is and a student who left before the next pull stays),
#'   `total_credits_entering`,
#'   `total_credits_after`, and `timeline_valid` (FALSE when the student's first
#'   term in the data is the first term of the data, so their earlier
#'   coursework is invisible and the running total starts too low). All of
#'   these are ATTEMPTED credits. With `opt$earned`, before `timeline_valid`:
#'   `unm_earned_entering`, `unm_earned_after` (completed here, before and
#'   after the term), `transfer_earned`, `transfer_earned_known` (as
#'   `transfer_credits_known`, for the earned pair), `total_earned_entering`
#'   and `total_earned_after`.
build_credit_timeline <- function(student_terms, programs = NULL, opt = list()) {

  needed <- c("student_id", "term", "unm_credits_entering",
              "cumulative_attempted_unm_credits", "timeline_valid")
  earned <- isTRUE(opt$earned)
  if (earned) needed <- c(needed, "completed_unm_credits", "cumulative_completed_unm_credits")
  missing_cols <- setdiff(needed, names(student_terms))
  if (length(missing_cols) > 0) {
    stop("[credit-timeline.R] student_terms is missing required column(s): ",
         paste(missing_cols, collapse = ", "),
         ". Expected the cedar_student_terms table.")
  }

  st <- student_terms
  if (!is.null(opt$student_ids) && length(opt$student_ids) > 0) {
    st <- dplyr::filter(st, student_id %in% opt$student_ids)
  }
  if (nrow(st) == 0) {
    empty <- tibble::tibble(
      student_id = character(), term = integer(),
      unm_credits_entering = numeric(), unm_credits_after = numeric(),
      transfer_credits = numeric(), transfer_credits_known = logical(),
      total_credits_entering = numeric(),
      total_credits_after = numeric()
    )
    if (earned) {
      empty <- dplyr::mutate(empty, unm_earned_entering = numeric(), unm_earned_after = numeric(),
                             transfer_earned = numeric(), transfer_earned_known = logical(),
                             total_earned_entering = numeric(), total_earned_after = numeric())
    }
    return(dplyr::mutate(empty, timeline_valid = logical()))
  }

  # Attempted basis throughout. The transfer block below is a difference of two
  # attempted columns, so pairing it with completed UNM credits would add
  # attempted transfer hours to completed UNM hours and silently inflate anyone
  # who failed or withdrew from a course.
  timeline <- st %>%
    dplyr::transmute(
      student_id, term,
      unm_credits_entering,
      unm_credits_after = cumulative_attempted_unm_credits,
      # The table sets the flag over the whole data; an NA here is a row the
      # builder could not place, and unknown is not valid.
      timeline_valid = !is.na(timeline_valid) & timeline_valid
    ) %>%
    dplyr::arrange(student_id, term)

  transfer <- .credit_timeline_transfer_block(programs, unique(timeline$student_id))

  out <- timeline %>%
    dplyr::left_join(transfer, by = "student_id") %>%
    dplyr::mutate(
      transfer_credits_known = !is.na(transfer_credits),
      transfer_credits       = dplyr::coalesce(transfer_credits, 0),
      total_credits_entering = transfer_credits + unm_credits_entering,
      total_credits_after    = transfer_credits + unm_credits_after
    ) %>%
    dplyr::select(student_id, term, unm_credits_entering, unm_credits_after,
                  transfer_credits, transfer_credits_known, total_credits_entering, total_credits_after,
                  timeline_valid)
  if (!earned) return(out)

  # The earned position, on the same rows. Completed here before the term is
  # the running total less the term's own: a term with no completed credits
  # recorded (NA) leaves the position unknown, never zero.
  here <- st %>%
    dplyr::transmute(student_id, term,
                     unm_earned_entering = cumulative_completed_unm_credits - completed_unm_credits,
                     unm_earned_after = cumulative_completed_unm_credits)
  brought <- .credit_timeline_transfer_block(programs, unique(timeline$student_id),
                                             inst = "inst_credits_earned", overall = "overall_credits_earned") %>%
    dplyr::rename(transfer_earned = transfer_credits)
  out %>%
    dplyr::left_join(here, by = c("student_id", "term")) %>%
    dplyr::left_join(brought, by = "student_id") %>%
    dplyr::mutate(
      transfer_earned_known = !is.na(transfer_earned),
      transfer_earned       = dplyr::coalesce(transfer_earned, 0),
      total_earned_entering = transfer_earned + unm_earned_entering,
      total_earned_after    = transfer_earned + unm_earned_after
    ) %>%
    dplyr::relocate(timeline_valid, .after = dplyr::last_col())
}


#' Which Students Have a Readable Credit Timeline
#'
#' The `timeline_valid` rule over a raw (student, term) frame, for the one
#' reader that still builds its own running series from class-list rows:
#' [build_gpa_timeline()]. The credit position itself no longer needs this —
#' `cedar_student_terms` carries `timeline_valid`, set by
#' `build_student_terms()` over the whole data — and a reader with that table
#' in hand reads the column rather than re-deriving it. Kept so there is still
#' exactly one definition of "we can see this student's whole record" for a
#' series built from rows; a second local rule is how the two drift apart.
#'
#' Needs only `student_id` and `term`.
#'
#' @param rows Data frame with `student_id` and `term`, **unsliced by term**
#'   where possible — see `opt$student_first_terms`.
#' @param opt List of options:
#'   \describe{
#'     \item{`student_ids`}{Character vector. Restrict to these students.}
#'     \item{`min_data_term`}{Integer. First term present in the data. Defaults
#'       to the earliest term in `rows`.}
#'     \item{`student_first_terms`}{Data frame with `student_id` and
#'       `first_unm_term`. **Required if you pre-filtered `rows` by term.**
#'       Filtering to `term >= X` hides exactly the early rows that make a
#'       student invalid, and every one of them would then be marked valid.}
#'   }
#' @return Tibble of `student_id` and `timeline_valid`.
credit_timeline_validity <- function(rows, opt = list()) {

  missing_cols <- setdiff(c("student_id", "term"), names(rows))
  if (length(missing_cols) > 0) {
    stop("[credit-timeline.R] rows is missing required column(s): ",
         paste(missing_cols, collapse = ", "))
  }

  tc <- rows
  if (!is.null(opt$student_ids) && length(opt$student_ids) > 0) {
    tc <- dplyr::filter(tc, student_id %in% opt$student_ids)
  }

  # Read from the FULL table, not the population slice: the window opens where
  # the data opens, not where this cohort happens to start.
  min_data_term <- opt$min_data_term %||%
    suppressWarnings(min(rows$term, na.rm = TRUE))

  # First terms come from the caller when supplied, and otherwise from the input
  # itself. See the student_first_terms note above for why the distinction
  # matters: read off a term-filtered slice this guard fails open, marking every
  # student valid, which is the one direction it must never fail.
  first_terms <- opt$student_first_terms
  if (!is.null(first_terms)) {
    if (!all(c("student_id", "first_unm_term") %in% names(first_terms))) {
      stop("[credit-timeline.R] opt$student_first_terms needs columns ",
           "student_id and first_unm_term.")
    }
    first_terms <- dplyr::filter(first_terms, student_id %in% unique(tc$student_id))
  } else {
    first_terms <- tc %>%
      dplyr::group_by(student_id) %>%
      dplyr::summarize(first_unm_term = min(term, na.rm = TRUE), .groups = "drop")
  }

  tibble::tibble(student_id = unique(tc$student_id)) %>%
    dplyr::left_join(first_terms, by = "student_id") %>%
    # NA first term means the caller supplied a lookup that does not cover this
    # student. Unknown is not the same as fine — fail closed.
    dplyr::mutate(timeline_valid = !is.na(first_unm_term) & first_unm_term > min_data_term) %>%
    dplyr::select(student_id, timeline_valid)
}


# Transfer credit, recovered as the gap between the two frozen cumulative
# columns. Both are stamped at the same pull instant, so the difference between
# them is not affected by the freeze even though neither value is usable alone.
# Median across the student's rows, because the pair is only stable across a
# student's records 93% of the time and a median ignores the odd restated row.
# Negative results are floored at zero: overall < institution is a data error,
# not negative transfer credit.
# `inst` and `overall` name the pair: attempted by default, the earned pair
# for the earned position.
.credit_timeline_transfer_block <- function(programs, student_ids, inst = "inst_credits_attempted",
                                            overall = "overall_credits_attempted") {
  empty <- tibble::tibble(student_id = character(), transfer_credits = numeric())
  if (is.null(programs)) return(empty)

  if (!all(c("student_id", inst, overall) %in% names(programs))) {
    stop("[credit-timeline.R] programs must have student_id, ",
         inst, " and ", overall, " to recover ",
         "transfer credit. Pass programs = NULL for a UNM-only timeline.")
  }

  block <- programs %>%
    dplyr::filter(student_id %in% student_ids,
                  !is.na(.data[[inst]]), !is.na(.data[[overall]])) %>%
    dplyr::distinct(student_id, inst_value = .data[[inst]], overall_value = .data[[overall]]) %>%
    dplyr::mutate(gap = overall_value - inst_value) %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(transfer_credits = max(stats::median(gap, na.rm = TRUE), 0),
                     .groups = "drop")

  if (nrow(block) == 0) return(empty)
  block
}


#' Attach a Credit Position to Rows Keyed by Student and Term
#'
#' Join helper for the common case: a table of events (a major change, a course
#' enrollment, a declaration) that needs "how far along were they".
#'
#' @param events Data frame with `student_id` and a term column.
#' @param timeline Data frame from [build_credit_timeline()].
#' @param term_col Character. Name of the term column on `events`. Default `"term"`.
#' @param basis Character. `"total"` (default, includes transfer) or `"unm"`.
#'
#' @return `events` with `credits_entering` and `timeline_valid` added. Rows with
#'   no matching timeline entry get NA rather than being dropped — an event in a
#'   term the student has no row for is real and should stay visible, just
#'   without a credit position.
attach_credit_position <- function(events, timeline, term_col = "term",
                                   basis = c("total", "unm")) {
  basis <- match.arg(basis)
  if (!term_col %in% names(events)) {
    stop("[credit-timeline.R] events has no column '", term_col, "'.")
  }
  col <- if (basis == "total") "total_credits_entering" else "unm_credits_entering"

  events %>%
    dplyr::left_join(
      timeline %>% dplyr::select(student_id, term,
                                 credits_entering = dplyr::all_of(col), timeline_valid),
      by = stats::setNames(c("student_id", "term"), c("student_id", term_col))
    )
}
