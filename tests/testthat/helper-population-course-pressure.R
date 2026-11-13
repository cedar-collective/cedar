# What the tests in test-population-course-pressure.R share: builders, option lists, constants.

hp2_edges <- function() cedar_data_edges(test_students_hp2)

hp2_attempts <- function() attempts_for(test_students_hp2, hp2_edges())

hp2_course_terms <- function() course_terms_for(test_students_hp2, test_sections_hp2, hp2_edges())

hp2_population <- function() {
  suppressMessages(build_population(
    test_programs_hp2, opt = list(type = "preset", program_names = "Nursing")
  ))
}

hp2_courses <- c("BIOL 1140", "CHEM 1215", "NUTR 2110")

hp2_plans <- tibble::tribble(
  ~catalog_id,        ~subject_course,
  "nursing-bsn-2026", "BIOL 1140",
  "nursing-bsn-2026", "CHEM 1215",
  "medlab-bs-2026",   "BIOL 1140",
  "medlab-bs-2026",   "NUTR 2110",
  "pophealth-bs-2026", "BIOL 1140"
)
