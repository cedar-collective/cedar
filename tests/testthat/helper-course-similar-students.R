# What the tests in test-course-similar-students.R share: builders, option lists, constants.

.ss_row <- function(sid, term_code, outcome_value, instructor = "RP_I1") {
  ss_attempts %>% slice(1L) %>%
    mutate(student_id = sid, term = as.integer(term_code), subject_course = "HIST 101",
           outcome = outcome_value, instructor_id = instructor, instructor_name = instructor)
}

ss_opt <- function(...) c(list(classification = "Freshman", min_n = 1L, min_cell_n = 1L, data_edges = rp01_edges),
                          list(...))
