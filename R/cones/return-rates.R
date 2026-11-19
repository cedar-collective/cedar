# return-rates.R — How often do enrolled students come back the next regular
# term?
#
# A filter and a count over cedar_student_terms, CEDAR's one definition of an
# enrolled student-term and of return (docs/developers/student-terms.md): the
# population is every enrolled student-term of the scope, the outcome
# `returned_next_regular_term`, read UNM-wide (moving campus is not leaving).
# A student-term whose next regular term is past the settled edge, or has no
# class list, is not observable and stays out of the rate, counted; so does a
# student awarded a degree that term, who completed rather than left.
#
# Groups are the table's own descriptions (home campus, classification,
# primary college) and two warning signs known by the end of the term: a late
# withdrawal (`late_withdrawals` > 0) and a DFW grade (`dfw_grades` > 0, late
# drops counted apart). The DFW sign needs posted grades: past `last_graded`,
# or with no graded row, it is unknown (NA), never "no DFW".
#
# Depends on: get_term_type() (trunk/utils.R)

RETURN_RATE_GROUPS <- c("student_campus", "student_classification", "primary_college_code",
                        "late_withdrawal", "dfw")

#' Return to the next regular term, per anchor term and group
#'
#' @param student_terms `cedar_student_terms`.
#' @param opt `data_edges` (required: `last_enrolled_complete`, and
#'   `last_graded` for the DFW sign), `term_type` (anchor term types; NULL
#'   keeps every type), `student_level` (level codes; NULL keeps every level),
#'   `campus` (home campuses; NULL keeps every campus), `group_cols` (any of
#'   `RETURN_RATE_GROUPS`; empty for one row a term), `min_n` (observable
#'   student-terms a row needs for a rate; default 10).
#' @return list(rates, meta). `rates`: one row per `term` and group with
#'   `n_enrolled`, `n_graduated` (awarded a degree that term), `n_unobservable`,
#'   `n_observable`, `n_returned` and `return_pct` (NA under `min_n`).
#'   `meta`: the options and both edges.
get_return_rates <- function(student_terms, opt = list()) {
  needed <- c("student_id", "term", "enrolled", "student_level", "student_campus",
              "returned_next_regular_term", "return_observable", "degree_awarded")
  group_cols <- opt$group_cols %||% character(0)
  bad <- setdiff(group_cols, RETURN_RATE_GROUPS)
  if (length(bad) > 0L) {
    stop("[return-rates.R] opt$group_cols must be among ", paste(RETURN_RATE_GROUPS, collapse = ", "),
         "; not ", paste(bad, collapse = ", "), call. = FALSE)
  }
  needed <- c(needed, setdiff(group_cols, c("late_withdrawal", "dfw")),
              if ("late_withdrawal" %in% group_cols) "late_withdrawals",
              if ("dfw" %in% group_cols) c("dfw_grades", "graded_rows"))
  missing <- setdiff(needed, names(student_terms))
  if (length(missing) > 0L) {
    stop("[return-rates.R] student_terms lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[return-rates.R] opt$data_edges has no settled enrollment edge.", call. = FALSE)
  }
  graded_edge <- opt$data_edges[["last_graded"]]
  if ("dfw" %in% group_cols && is.null(graded_edge)) {
    stop("[return-rates.R] the DFW sign needs opt$data_edges' graded edge (last_graded).", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)

  rows <- student_terms %>% filter(enrolled, term <= edge)
  if (!is.null(opt$term_type)) rows <- rows %>% filter(get_term_type(term) %in% opt$term_type)
  if (!is.null(opt$student_level)) rows <- rows %>% filter(student_level %in% opt$student_level)
  if (!is.null(opt$campus)) rows <- rows %>% filter(student_campus %in% opt$campus)
  if ("late_withdrawal" %in% group_cols) rows <- rows %>% mutate(late_withdrawal = late_withdrawals > 0L)
  if ("dfw" %in% group_cols) {
    rows <- rows %>% mutate(dfw = if_else(term <= graded_edge & graded_rows > 0L, dfw_grades > 0L, NA))
  }
  cedar_debug("[return-rates.R] ", nrow(rows), " enrolled student-terms to ", fmt_term(edge))

  rates <- rows %>%
    mutate(graduated = degree_awarded %in% TRUE,
           observable = !graduated & return_observable %in% TRUE) %>%
    group_by(term, across(all_of(group_cols))) %>%
    summarize(
      n_enrolled = n(),
      n_graduated = sum(graduated),
      n_unobservable = sum(!graduated & !observable),
      n_observable = sum(observable),
      n_returned = sum(observable & returned_next_regular_term %in% TRUE),
      .groups = "drop"
    ) %>%
    mutate(return_pct = if_else(n_observable >= min_n, 100 * n_returned / n_observable, NA_real_)) %>%
    arrange(term, across(all_of(group_cols)))

  list(rates = rates,
       meta = list(term_type = opt$term_type, student_level = opt$student_level, campus = opt$campus,
                   group_cols = group_cols, min_n = min_n, edge = edge, graded_edge = graded_edge))
}
