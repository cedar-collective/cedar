# What the tests in test-pathway.R share: builders, option lists, constants.

# The position columns of cedar_student_terms for the S00x students, as
# build_student_terms() would write them: running totals per student, and
# timeline_valid set against the first term in the whole table. `extra` rows
# are bound in before either is derived, so a row on an earlier term opens the
# window for everyone.
make_pathway_student_terms <- function(extra = NULL) {
  dplyr::bind_rows(
    tibble(
      student_id = c("S001", "S001", "S001",
                     "S002", "S002", "S002",
                     "S003", "S003",
                     "S004", "S004", "S004",
                     "S005", "S005"),
      term = c(202410L, 202480L, 202510L,
               202410L, 202480L, 202510L,
               202410L, 202480L,
               202410L, 202480L, 202510L,
               202480L, 202510L),
      attempted_unm_credits = rep(15, 13),
      completed_unm_credits = rep(15, 13),
      # The classification each student carried that term, as the class-list
      # fixture above records it; the classification axis and the start filter
      # read it from here, never from the course row.
      student_classification = c("Freshman", "Sophomore", "Junior",
                                 "Freshman", "Sophomore", "Junior",
                                 "Freshman", "Sophomore",
                                 "Freshman", "Sophomore", "Junior",
                                 "Sophomore", "Junior"),
      enrolled = TRUE
    ),
    extra
  ) %>%
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

# MC02 in designed_test_data.R supplies the two-campus rows; the population
# wrapper is shape, not data.
mc_population <- function(ids) {
  tibble(student_id = ids, population_label = "MC test population")
}
