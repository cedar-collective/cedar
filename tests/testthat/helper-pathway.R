# What the tests in test-pathway.R share: builders, option lists, constants.

make_pathway_students <- function() {
  tibble(
    student_id = c(
      "S001", "S001", "S001",
      "S002", "S002", "S002",
      "S003", "S003",
      "S004", "S004", "S004",
      "S005", "S005"
    ),
    term = c(
      202410L, 202480L, 202510L,
      202410L, 202480L, 202510L,
      202410L, 202480L,
      202410L, 202480L, 202510L,
      202480L, 202510L
    ),
    subject_course = c(
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "CHEM 1215", "BIOL 2310",
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "BIOL 2310",  "ENGL 1110"
    ),
    course_title = c(
      "General Chemistry", "General Biology", "Composition",
      "General Chemistry", "General Biology", "Composition",
      "General Chemistry", "General Biology",
      "General Chemistry", "General Biology", "Composition",
      "General Biology",   "Composition"
    ),
    student_classification = c(
      "Freshman",  "Sophomore", "Junior",
      "Freshman",  "Sophomore", "Junior",
      "Freshman",  "Sophomore",
      "Freshman",  "Sophomore", "Junior",
      "Sophomore", "Junior"
    ),
    registration_status_code = rep("RE", 13),
    # All ABQ: the timing and pairs expectations in test-pathway.R are stated
    # per course, so a single campus keeps them one row each. The two-campus
    # behaviour is pinned separately at the end of that file.
    campus = rep("ABQ", 13)
  )
}

make_pathway_population <- function() {
  tibble(
    student_id       = c("S001", "S002", "S003", "S004", "S005"),
    population_label = "bio_majors"
  )
}

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

make_ep_population <- function() {
  tibble(
    student_id       = c("S001", "S002", "S003", "S004", "S005", "S006", "S007"),
    population_label = "bio_majors",
    outcome          = c("ongoing", "ongoing", "ongoing",
                         "chose_elsewhere", "chose_elsewhere",
                         "ongoing",    # S006: entered, but first_unit_term=202410 (no prior)
                         "ongoing"),   # S007: switched_in, still "entered" by outcome
    entry_status     = c("pre_major", "pre_major", "pre_major",
                         "pre_major", "pre_major",
                         "pre_major",
                         "switched_in"),
    first_unit_term  = c(202480L, 202480L, 202480L,
                         202480L, 202480L,
                         202410L,   # earliest data term — no prior term exists
                         202480L),
    last_unit_term   = c(202510L, 202510L, 202510L,
                         202480L, 202480L,
                         202510L,
                         202510L)
  )
}

make_ep_students <- function() {
  tibble(
    student_id = c(
      # 202410: prior term window for first_unit_term=202480 students
      "S001", "S002", "S003", "S004", "S007",  # CHEM 1215 (S007 switched_in, now included)
      "S002", "S003", "S004", "S005",          # HIST 101
      "S006",                                  # PHYS 100 (S006 excluded: no prior term)
      # 202480: event term itself — should NOT appear in results
      "S001", "S002", "S003", "S004", "S005",
      # 202510: post-event — should NOT appear in results
      "S001", "S002"
    ),
    term = c(
      202410L, 202410L, 202410L, 202410L, 202410L,
      202410L, 202410L, 202410L, 202410L,
      202410L,
      202480L, 202480L, 202480L, 202480L, 202480L,
      202510L, 202510L
    ),
    subject_course = c(
      "CHEM 1215", "CHEM 1215", "CHEM 1215", "CHEM 1215", "CHEM 1215",
      "HIST 101",  "HIST 101",  "HIST 101",  "HIST 101",
      "PHYS 100",
      "BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310",
      "BIOL 3100", "BIOL 3100"
    ),
    course_title = c(
      rep("General Chemistry", 5),
      rep("World History",     4),
      rep("Physics",           1),
      rep("General Biology",   5),
      rep("Cell Biology",      2)
    ),
    registration_status_code = rep("RE", 17),
    campus = rep("ABQ", 17)
  )
}

# MC02 in designed_test_data.R supplies the two-campus rows; the population
# wrapper is shape, not data.
mc_population <- function(ids) {
  tibble(student_id = ids, population_label = "MC test population")
}
