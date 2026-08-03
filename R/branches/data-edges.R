# data-edges.R — where the data actually starts and stops
#
# THE PROBLEM
#
# CEDAR's local data is always behind the registrar, and a term does not arrive
# all at once. Registration for a future term appears months early; grades for a
# finished term land weeks late. So at any moment the tail of the data looks
# like this:
#
#   Fall 2025    128k rows   91% graded   <- finished and gradeable
#   Spring 2026  119k rows    7% graded   <- finished, grades still landing
#   Summer 2026   15k rows    0% graded   <- registration only
#   Fall 2026     85k rows    0% graded   <- registration only, partial
#
# An analysis bounded by the wrong edge produces a confident wrong number rather
# than an error. Measured before this file existed: the DFW rate for Spring 2026
# read 0.3% against 6-8% for every other term, because the denominator counted
# all 104,431 attempts while the numerator could only see the 7% of grades that
# had posted. Every DFW surface in the app showed it as a dramatic improvement.
#
# WHY CONFIG ARITHMETIC IS NOT THE ANSWER
#
# `cedar_report_end_term <- subtract_term(cedar_current_term)` encodes a guess
# that exactly one term is in flight. It goes stale (grades land, nothing moves
# until someone edits config) and it can overshoot (config set ahead of the data
# nominates a term with no grades at all). The edges below are read from the
# data, so they are correct on whatever snapshot is loaded and move on their own.
#
# WHICH EDGE TO USE — this is the part that matters
#
#   last_graded             anything that reads a grade: DFW, pass rates, grade
#                           distributions, stop-out after a DFW, outcomes.
#   last_enrolled_complete  enrollment reporting: headcount, seats, fill rates,
#                           credit hours. The last term whose registration has
#                           actually settled.
#   last_enrolled           every term with any rows at all, including one still
#                           filling. Use only when you want the raw extent of
#                           the data, not a reporting boundary.
#   last_degree             completions.
#
# Using last_enrolled for a grade question is the bug described above. Using
# last_enrolled for an ENROLLMENT report is the same bug one step over: a term
# captured months before it starts is advance registration, and charting it
# beside settled terms shows a cliff that is an artifact of the pull date.
#
# HOW "SETTLED" IS DECIDED, AND WHY NOT BY SIZE
#
# A term counts as settled when the newest pull covering it happened at least
# `min_days_after_start` days after the term began. Comparing a term's row count
# against the same season in prior years separates the cases just as cleanly on
# current data (Fall 2026 sits at 71% of a typical fall), but it has a failure
# mode this does not: a genuine enrollment decline looks identical to an
# unfinished term, so a size rule would quietly truncate reports in exactly the
# year a chair most needs to see the drop. Pull timing cannot make that mistake
# — it describes when the data was captured, not how many students exist.


#' Where the loaded data starts and stops
#'
#' @param students Data frame. `cedar_students`. Required.
#' @param degrees Data frame or NULL. `cedar_degrees`, for `last_degree`.
#' @param min_graded_share Numeric 0-1. Share of a term's enrollment rows that
#'   must carry a final grade before the term counts as gradeable. Default
#'   `0.5`. The threshold is not finely balanced: on current data finished terms
#'   sit at 83-91% and in-flight terms at 0-7%, so anything from ~0.2 to ~0.8
#'   picks the same edge.
#' @param max_term Optional integer. Ignore anything after this — pass a
#'   configured end term to keep a deliberately restricted report window.
#' @param min_days_after_start Integer. How long after a term begins its data
#'   must have been pulled before the term counts as settled. Default `14`,
#'   which clears add/drop. Needs an `as_of_date` column; without one
#'   `last_enrolled_complete` is NULL rather than a guess.
#'
#' @return Named list: `first_enrolled`, `last_enrolled`, `last_graded`,
#'   `last_degree` (NULL when `degrees` is not supplied), and `graded_by_term`,
#'   a tibble of `term` / `rows` / `graded_share` so a caller can show its work
#'   rather than asserting an edge. Any edge that cannot be determined is NULL,
#'   never a guess.
cedar_data_edges <- function(students, degrees = NULL,
                             min_graded_share = 0.5, max_term = NULL,
                             min_days_after_start = 14L) {
  if (is.null(students) || nrow(students) == 0) {
    stop("[data-edges.R] cedar_data_edges() needs a non-empty students table.")
  }
  missing <- setdiff(c("term", "final_grade"), names(students))
  if (length(missing) > 0) {
    stop("[data-edges.R] students is missing required column(s): ",
         paste(missing, collapse = ", "))
  }

  scoped <- students %>% dplyr::filter(!is.na(term))
  if (!is.null(max_term)) scoped <- dplyr::filter(scoped, term <= max_term)
  if (nrow(scoped) == 0) {
    stop("[data-edges.R] No enrollment rows at or before max_term = ", max_term, ".")
  }

  by_term <- scoped %>%
    dplyr::group_by(term) %>%
    dplyr::summarize(
      rows = dplyr::n(),
      graded_share = mean(!is.na(final_grade) & nzchar(final_grade)),
      .groups = "drop"
    ) %>%
    dplyr::arrange(term)

  gradeable <- dplyr::filter(by_term, graded_share >= min_graded_share)

  # Settled-registration edge. Term start is approximated from the term code
  # (Fall mid-Aug, Spring mid-Jan, Summer mid-Jun) — CEDAR has no census-date
  # table, and the comparison is against a pull date months away, so a fortnight
  # of slop in the nominal start changes nothing.
  last_settled <- NULL
  if ("as_of_date" %in% names(scoped)) {
    pulls <- scoped %>%
      dplyr::filter(!is.na(as_of_date)) %>%
      dplyr::group_by(term) %>%
      dplyr::summarize(newest_pull = max(as_of_date), .groups = "drop") %>%
      dplyr::mutate(
        term_begins = .cedar_term_start(term),
        days_after_start = as.integer(newest_pull - term_begins)
      )
    by_term <- dplyr::left_join(by_term, pulls, by = "term")
    settled <- dplyr::filter(pulls, days_after_start >= min_days_after_start)
    if (nrow(settled) > 0) last_settled <- as.integer(max(settled$term))
  }

  last_degree <- NULL
  if (!is.null(degrees) && nrow(degrees) > 0 && "term" %in% names(degrees)) {
    d <- degrees
    if ("graduation_status" %in% names(d)) {
      d <- dplyr::filter(d, graduation_status == "Awarded")
    }
    if (!is.null(max_term)) d <- dplyr::filter(d, term <= max_term)
    d <- dplyr::filter(d, !is.na(term))
    if (nrow(d) > 0) last_degree <- as.integer(max(d$term))
  }

  list(
    first_enrolled = as.integer(min(by_term$term)),
    last_enrolled  = as.integer(max(by_term$term)),
    last_enrolled_complete = last_settled,
    last_graded    = if (nrow(gradeable) > 0) as.integer(max(gradeable$term)) else NULL,
    last_degree    = last_degree,
    graded_by_term = by_term,
    min_graded_share = min_graded_share,
    min_days_after_start = as.integer(min_days_after_start)
  )
}


# Nominal first day of a term, from its code. Fall = mid-August, Spring =
# mid-January, Summer = mid-June.
.cedar_term_start <- function(term) {
  yr <- term %/% 100L
  ss <- term %% 100L
  month <- dplyr::case_when(ss == 80L ~ 8L, ss == 10L ~ 1L, TRUE ~ 6L)
  as.Date(sprintf("%d-%02d-15", yr, month))
}


#' One-line description of an edge, for display
#'
#' Surfaces that cap a view should say which edge they used and why, so a reader
#' sees a data state rather than assuming a stale pipeline.
#'
#' @param edges Output of [cedar_data_edges()].
#' @param which Character. `"graded"` or `"enrolled"`.
#' @return Character string, or NULL if that edge is unavailable.
#' @keywords internal
cedar_edge_note <- function(edges, which = c("graded", "enrolled")) {
  which <- match.arg(which)
  if (is.null(edges)) return(NULL)

  if (which == "graded") {
    if (is.null(edges$last_graded)) return(NULL)
    nxt <- tryCatch(add_term(edges$last_graded), error = function(e) NULL)
    paste0(
      "Through ", fmt_term(edges$last_graded),
      ", the most recent term with grades posted.",
      if (!is.null(nxt) && !is.null(edges$last_enrolled) && nxt <= edges$last_enrolled) {
        paste0(" ", fmt_term(nxt), " is enrolled but not yet graded, so it cannot ",
               "carry a grade-based rate; it will appear once its grades load.")
      } else ""
    )
  } else {
    edge <- edges$last_enrolled_complete %||% edges$last_enrolled
    if (is.null(edge)) return(NULL)
    paste0(
      "Through ", fmt_term(edge), ", the most recent term whose registration has settled.",
      if (!is.null(edges$last_enrolled) && edge < edges$last_enrolled) {
        paste0(" ", fmt_term(edges$last_enrolled), " is still filling \u2014 its data was ",
               "captured before the term began, so charting it here would show a drop that ",
               "is an artifact of the pull date, not of enrollment.")
      } else ""
    )
  }
}
