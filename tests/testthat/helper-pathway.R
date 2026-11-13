# What the tests in test-pathway.R do: derive the position columns of a typed
# student-term table.

# The position columns of cedar_student_terms, as build_student_terms() would
# write them, over typed student-term rows: running totals per student, and
# timeline_valid set against the first term in the whole table, so a row on an
# earlier term opens the window for everyone.
pathway_position_columns <- function(rows) {
  rows %>%
    dplyr::mutate(.min_data_term = min(term)) %>%
    dplyr::group_by(student_id) %>%
    dplyr::arrange(term, .by_group = TRUE) %>%
    dplyr::mutate(
      cumulative_attempted_unm_credits = cumsum(attempted_unm_credits),
      cumulative_completed_unm_credits = cumsum(completed_unm_credits),
      unm_credits_entering = cumulative_attempted_unm_credits - attempted_unm_credits,
      timeline_valid = min(term) > .min_data_term
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.min_data_term)
}
