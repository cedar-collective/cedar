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
# UNM-side history is trustworthy: cedar_student_term_credits is derived from
# class lists, one row per enrolled term, and is a genuine running total. What it
# cannot see is credit the student arrived with.
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
#   * The UNM running total starts at zero on the first term IN THE DATA. For a
#     student already enrolled when the window opens, their timeline begins
#     mid-career reading zero. `timeline_valid` marks who this applies to;
#     callers must filter or caveat rather than quietly averaging them in.


#' Build a Per-Term Credit Position for Students
#'
#' One row per (student, enrolled term) giving how many credits the student had
#' *entering* that term — the figure that answers "where were they when they did
#' this" — and after completing it.
#'
#' @param term_credits Data frame. `cedar_student_term_credits`. Required; this
#'   is the trustworthy UNM series.
#' @param programs Data frame or NULL. `cedar_programs`, used only to recover
#'   each student's transfer block. NULL yields a UNM-only timeline with
#'   `transfer_credits = 0` and `total_*` equal to `unm_*`, which is honest but
#'   understates anyone who arrived with credit.
#' @param opt List of options:
#'   \describe{
#'     \item{`student_ids`}{Character vector. Restrict to these students. Strongly
#'       recommended — the full table is ~430k rows.}
#'     \item{`min_data_term`}{Integer. First term present in the enrollment data.
#'       Used to set `timeline_valid`. Defaults to the earliest term in
#'       `term_credits`.}
#'     \item{`student_first_terms`}{Data frame with `student_id` and
#'       `first_unm_term`. **Required if you pre-filtered `term_credits` by
#'       term.** `timeline_valid` asks whether a student's history starts inside
#'       the data, which cannot be read off a slice: filtering to
#'       `term <= grad_term` hides nothing, but filtering to `term >= X` hides
#'       exactly the early rows that make a student invalid, and every one of
#'       them would then be marked valid. Supplying this makes the guard immune
#'       to how the input was sliced.}
#'   }
#'
#' @return Tibble with `student_id`, `term`, `unm_credits_entering`,
#'   `unm_credits_after`, `transfer_credits`, `total_credits_entering`,
#'   `total_credits_after`, and `timeline_valid` (FALSE when the student's first
#'   term in the data is the first term of the data, so their earlier
#'   coursework is invisible and the running total starts too low).
build_credit_timeline <- function(term_credits, programs = NULL, opt = list()) {

  needed <- c("student_id", "term", "attempted_unm_credits",
              "cumulative_attempted_unm_credits")
  missing_cols <- setdiff(needed, names(term_credits))
  if (length(missing_cols) > 0) {
    stop("[credit-timeline.R] term_credits is missing required column(s): ",
         paste(missing_cols, collapse = ", "),
         ". Expected the cedar_student_term_credits table.")
  }

  tc <- term_credits
  if (!is.null(opt$student_ids) && length(opt$student_ids) > 0) {
    tc <- dplyr::filter(tc, student_id %in% opt$student_ids)
  }
  if (nrow(tc) == 0) {
    return(tibble::tibble(
      student_id = character(), term = integer(),
      unm_credits_entering = numeric(), unm_credits_after = numeric(),
      transfer_credits = numeric(), total_credits_entering = numeric(),
      total_credits_after = numeric(), timeline_valid = logical()
    ))
  }

  min_data_term <- opt$min_data_term %||% suppressWarnings(min(term_credits$term, na.rm = TRUE))

  # Attempted basis throughout. The transfer block below is a difference of two
  # attempted columns, so pairing it with completed UNM credits would add
  # attempted transfer hours to completed UNM hours and silently inflate anyone
  # who failed or withdrew from a course.
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
  } else {
    first_terms <- tc %>%
      dplyr::group_by(student_id) %>%
      dplyr::summarize(first_unm_term = min(term, na.rm = TRUE), .groups = "drop")
  }

  timeline <- tc %>%
    dplyr::arrange(student_id, term) %>%
    dplyr::group_by(student_id) %>%
    dplyr::mutate(
      unm_credits_after    = cumulative_attempted_unm_credits,
      unm_credits_entering = cumulative_attempted_unm_credits - attempted_unm_credits
    ) %>%
    dplyr::ungroup() %>%
    dplyr::left_join(first_terms, by = "student_id") %>%
    # NA first term means the caller supplied a lookup that does not cover this
    # student. Unknown is not the same as fine — fail closed.
    dplyr::mutate(timeline_valid = !is.na(first_unm_term) & first_unm_term > min_data_term) %>%
    dplyr::select(-first_unm_term)

  transfer <- .credit_timeline_transfer_block(programs, unique(timeline$student_id))

  timeline %>%
    dplyr::left_join(transfer, by = "student_id") %>%
    dplyr::mutate(
      transfer_credits       = dplyr::coalesce(transfer_credits, 0),
      total_credits_entering = transfer_credits + unm_credits_entering,
      total_credits_after    = transfer_credits + unm_credits_after
    ) %>%
    dplyr::select(student_id, term, unm_credits_entering, unm_credits_after,
                  transfer_credits, total_credits_entering, total_credits_after,
                  timeline_valid)
}


# Transfer credit, recovered as the gap between the two frozen cumulative
# columns. Both are stamped at the same pull instant, so the difference between
# them is not affected by the freeze even though neither value is usable alone.
# Median across the student's rows, because the pair is only stable across a
# student's records 93% of the time and a median ignores the odd restated row.
# Negative results are floored at zero: overall < institution is a data error,
# not negative transfer credit.
.credit_timeline_transfer_block <- function(programs, student_ids) {
  empty <- tibble::tibble(student_id = character(), transfer_credits = numeric())
  if (is.null(programs)) return(empty)

  if (!all(c("student_id", "inst_credits_attempted",
             "overall_credits_attempted") %in% names(programs))) {
    stop("[credit-timeline.R] programs must have student_id, ",
         "inst_credits_attempted and overall_credits_attempted to recover ",
         "transfer credit. Pass programs = NULL for a UNM-only timeline.")
  }

  block <- programs %>%
    dplyr::filter(student_id %in% student_ids,
                  !is.na(inst_credits_attempted), !is.na(overall_credits_attempted)) %>%
    dplyr::distinct(student_id, inst_credits_attempted, overall_credits_attempted) %>%
    dplyr::mutate(gap = overall_credits_attempted - inst_credits_attempted) %>%
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
#'   term the student had no graded enrollment in is real and should stay
#'   visible, just without a credit position.
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
