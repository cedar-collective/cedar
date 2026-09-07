# relative-terms.R — Relative term numbering (branch)
#
# Aligns students who started in different semesters by numbering each student's
# enrolled terms 1, 2, 3, ... so trajectories are comparable regardless of entry
# year. Shared computation: course timing and course pairs both align on it.
#
# Split out of R/cones/pathway.R.
#
# Depends on: nothing beyond dplyr.

#' Assign Relative Term Numbers to Enrollment Records
#'
#' For each student, ranks their enrolled terms chronologically (1 = first term,
#' 2 = second, etc.) and adds a `relative_term` column.
#'
#' UNM term codes are YYYYSS format (e.g., 202510 = Spring 2025, 202560 = Summer,
#' 202580 = Fall). Numeric sort order is chronological order, so no external
#' lookup is needed.
#'
#' Summer terms (SS = "60") can be excluded from the counter — they don't
#' advance the relative term number but summer courses are still assigned to
#' the relative term of the preceding non-summer term.
#'
#' @param enrolled Data frame with columns: `student_id`, `term`.
#' @param include_summer Logical. Whether summer counts as its own relative
#'   term. Default: `FALSE`.
#'
#' @return `enrolled` with a `relative_term` integer column added.
#'
#' @keywords internal
assign_relative_terms <- function(enrolled, include_summer = FALSE) {

  # Tag each row with its integer term code and whether it's a summer term.
  # UNM term codes end in "60" for summer (e.g., 202560 = Summer 2025).
  enrolled <- enrolled %>%
    mutate(
      term_int  = as.integer(term),
      is_summer = substr(as.character(term), 5, 6) == "60"
    )

  if (!include_summer) {
    # --- Summer-excluded mode (default) ---
    # Summer does not count as its own relative term. A student whose first
    # three enrolled terms are Fall, Summer, Spring is treated as having two
    # relative terms, not three. Summer courses are assigned the relative_term
    # of the immediately preceding fall or spring.
    #
    # Implementation: rank non-summer terms per student, then combine with
    # summer terms (rank = NA) and forward-fill. This replaces the previous
    # many-to-many join approach and is O(N log N) instead of O(N × M).

    # Step A: rank each student's non-summer terms in chronological order
    non_summer_ranks <- enrolled %>%
      filter(!is_summer) %>%
      select(student_id, term_int) %>%
      distinct() %>%
      arrange(student_id, term_int) %>%
      group_by(student_id) %>%
      mutate(relative_term = row_number()) %>%
      ungroup()

    # Step B: combine ranked non-summer + unranked summer rows, sorted by
    # (student, term). Forward-fill propagates each non-summer rank to all
    # subsequent summer rows for the same student. coalesce(1L) handles the
    # edge case where a student's first enrolled term is summer.
    term_rterm <- bind_rows(
      non_summer_ranks,
      enrolled %>%
        filter(is_summer) %>%
        select(student_id, term_int) %>%
        distinct() %>%
        mutate(relative_term = NA_integer_)
    ) %>%
      distinct(student_id, term_int, .keep_all = TRUE) %>%
      arrange(student_id, term_int) %>%
      group_by(student_id) %>%
      tidyr::fill(relative_term) %>%                       # forward-fill summer ranks
      mutate(relative_term = dplyr::coalesce(relative_term, 1L)) %>%   # leading-summer edge case
      ungroup()

  } else {
    # --- Summer-included mode ---
    # Every term (including summer) advances the relative term counter.
    term_rterm <- enrolled %>%
      select(student_id, term_int) %>%
      distinct() %>%
      arrange(student_id, term_int) %>%
      group_by(student_id) %>%
      mutate(relative_term = row_number()) %>%
      ungroup()
  }

  # Join the relative_term back onto the original enrollment rows
  enrolled %>%
    left_join(term_rterm %>% select(student_id, term_int, relative_term),
              by = c("student_id", "term_int")) %>%
    select(-term_int, -is_summer)
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
