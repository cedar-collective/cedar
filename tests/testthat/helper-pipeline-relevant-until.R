# What the tests in test-pipeline-relevant-until.R share: builders, option lists, constants.

# Fixtures here are deliberately local: the relevant_until window turns on exact
# term spacing that the shared fixture does not provide. See AGENTS.md.
make_pipeline_students <- function() {
  tibble(
    student_id = c(
      "STU_ONGOING", "STU_ONGOING", "STU_ONGOING",
      "STU_BOUNDED", "STU_BOUNDED", "STU_BOUNDED"
    ),
    term = c(
      202410L, 202480L, 202510L,
      202410L, 202480L, 202510L
    ),
    subject_course = c(
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "CHEM 1215", "BIOL 2310", "ENGL 1110"
    ),
    course_title = c(
      "General Chemistry", "General Biology", "Composition",
      "General Chemistry", "General Biology", "Composition"
    ),
    student_classification   = rep("Freshman", 6),
    registration_status_code = rep("RE", 6),
    campus                   = rep("ABQ", 6)
  )
}

make_pipeline_population <- function() {
  tibble(
    student_id       = c("STU_ONGOING", "STU_BOUNDED"),
    population_label = "test",
    relevant_until   = c(NA_integer_, 202480L)
  )
}
