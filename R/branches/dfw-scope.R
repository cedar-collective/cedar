# The rows every DFW dashboard cone shares (Bird's Eye > DFW).
#
#   prepare_dfw_attempts()   the attempts in scope, one term type, flagged
#   dfw_window_terms()       the last terms of the type with an attempt
#
# The rows are cedar_attempts' (the outcome hub's prepare_course_attempts()),
# flagged with attempt_outcome_flags() under the default policy: A+ through C
# and CR pass; every other recorded grade and every late withdrawal is DFW;
# an early drop is in no denominator. The cones count them with the hub's
# one counter, summarize_attempt_outcomes(), whose columns say what the DFW
# grades were (W, F, D, C-, other nonpassing) and how many were NR, a grade
# the instructor did not post, counted as DFW like any other: a term with
# many of them reads high for that reason (ISSUES I61).
#
# Exported functions:
#   prepare_dfw_attempts(attempts, opt)
#   dfw_window_terms(rows, n_window)

DFW_TERM_TYPES <- c("fall", "spring", "summer")

#' The DFW attempts in scope
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param opt `term_type` (required: "fall", "spring" or "summer"), `level`
#'   (default "lower"), `campus` (the teaching campus; NULL for every campus),
#'   `data_edges` (optional; must agree with the table's graded edge).
#' @return The denominator attempts of that term type (graded or late
#'   withdrawn), with attempt_outcome_flags()' columns; attribute
#'   `graded_edge`.
prepare_dfw_attempts <- function(attempts, opt = list()) {
  edge <- require_attempts_build(attempts, "prepare_dfw_attempts")
  term_type <- opt$term_type
  if (is.null(term_type) || length(term_type) != 1L || !term_type %in% DFW_TERM_TYPES) {
    stop("[dfw-scope.R] opt$term_type must be one of ", paste(DFW_TERM_TYPES, collapse = ", "),
         "; a DFW series is read one term type at a time.", call. = FALSE)
  }
  level <- opt$level %||% "lower"
  scoped <- prepare_course_attempts(attempts, list(
    level = level, course_campus = opt$campus, data_edges = opt$data_edges))
  rows <- scoped %>%
    dplyr::filter(get_term_type(term) == .env$term_type) %>%
    attempt_outcome_flags() %>%
    dplyr::filter(is_denominator_attempt)
  cedar_debug("[dfw-scope.R] ", nrow(rows), " ", level, "-division ", term_type,
              " attempts graded through ", edge)
  attr(rows, "graded_edge") <- edge
  rows
}

#' The last terms of the type that hold an attempt
#'
#' @param rows prepare_dfw_attempts() output.
#' @param n_window How many terms.
#' @return Integer term codes, newest first; fewer when the history is shorter.
dfw_window_terms <- function(rows, n_window) {
  n_window <- as.integer(n_window)
  if (length(n_window) != 1L || is.na(n_window) || n_window < 1L) {
    stop("[dfw-scope.R] the window must be a whole number of terms, 1 or more.", call. = FALSE)
  }
  terms <- sort(unique(as.integer(rows$term)), decreasing = TRUE)
  if (length(terms) == 0L) {
    stop("[dfw-scope.R] no attempt is in scope, so there is no window to read.", call. = FALSE)
  }
  utils::head(terms, n_window)
}
