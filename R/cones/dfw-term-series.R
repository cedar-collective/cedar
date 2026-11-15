# How has the DFW rate moved, term by term?
#
# One term type at a time (a Fall's students are not a Spring's), for UNM as
# a whole or by a grouping (campus, college): each term's DFW rate and what
# its DFW grades were (W, F, D, C-, other; NRs apart), and a verdict on the
# line through the terms, judged against chance and the terms' own scatter
# (compute_rate_trend()). A term with fewer than `min_term_n` attempts in a
# group is listed and left out of that group's line.
#
# Exported functions:
#   get_dfw_term_series(attempts, opt, group_cols)

#' The DFW rate term by term, with its trend
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param opt prepare_dfw_attempts()' options (`term_type` required, `level`,
#'   `campus`, `data_edges`), plus `min_term_n` (default 30) and
#'   `min_trend_terms` (default 4).
#' @param group_cols `character()` for UNM as a whole, or columns of the
#'   attempts to read apart (`"campus"`, `"college"`).
#' @return A list: `terms` (one row per group and term:
#'   summarize_attempt_outcomes()' columns and `in_trend`), `trend` (one row per group: compute_rate_trend()'
#'   columns), `meta` (`term_type`, `level`, `campus`, `group_cols`,
#'   `graded_edge`, `min_term_n`, `min_trend_terms`).
get_dfw_term_series <- function(attempts, opt = list(), group_cols = character()) {
  allowed <- c("campus", "college")
  if (length(setdiff(group_cols, allowed))) {
    stop("[dfw-term-series.R] group_cols may hold only ", paste(allowed, collapse = ", "), call. = FALSE)
  }
  min_term_n <- as.integer(opt$min_term_n %||% 30L)
  min_trend_terms <- as.integer(opt$min_trend_terms %||% 4L)
  rows <- prepare_dfw_attempts(attempts, opt)
  if (nrow(rows) == 0L) {
    stop("[dfw-term-series.R] no ", opt$level %||% "lower", "-division ", opt$term_type,
         " attempt is in scope.", call. = FALSE)
  }
  terms <- summarize_attempt_outcomes(rows, c(group_cols, "term")) %>%
    dplyr::mutate(in_trend = n_attempts >= min_term_n) %>%
    dplyr::arrange(dplyr::across(dplyr::all_of(group_cols)), term)
  trend <- terms %>%
    dplyr::filter(in_trend) %>%
    dplyr::transmute(dplyr::across(dplyr::all_of(group_cols)), term, k = n_dfw, n = n_attempts) %>%
    compute_rate_trend(group_cols, min_terms = min_trend_terms)
  cedar_debug("[dfw-term-series.R] ", nrow(terms), " group-terms, ", nrow(trend), " lines")
  list(
    terms = terms,
    trend = trend,
    meta = list(term_type = opt$term_type, level = opt$level %||% "lower", campus = opt$campus,
                group_cols = group_cols, graded_edge = attr(rows, "graded_edge"),
                min_term_n = min_term_n, min_trend_terms = min_trend_terms)
  )
}
