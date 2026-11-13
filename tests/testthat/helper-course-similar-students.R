# What the tests in test-course-similar-students.R share: builders, option lists, constants.

ss_attempts <- function() keyed_attempts(test_students_rp, rp01_edges)

.ss_row <- function(sid, term_code, outcome_value, instructor = "RP_I1") {
  ss_attempts() %>% slice(1L) %>%
    mutate(student_id = sid, term = as.integer(term_code), subject_course = "HIST 101",
           outcome = outcome_value, instructor_id = instructor, instructor_name = instructor)
}

ss_attempts2 <- function() {
  bind_rows(
    ss_attempts(),
    .ss_row("RP_BACK", 202010, "pass"), .ss_row("RP_FAIL", 202010, "pass", "RP_I3"),
    .ss_row("RP_REP", 202080, "dfw"), .ss_row("RP_BACK", 202080, "pass"), .ss_row("RP_FAIL", 202080, "dfw")
  )
}

ss_student_terms2 <- function() {
  test_student_terms_rp %>%
    mutate(sem_gpa = case_when(
      term == 202080L & student_id == "RP_BACK" ~ 3.0,
      term == 202080L & student_id == "RP_FAIL" ~ 2.0,
      term == 202080L & student_id == "RP_REP" ~ 4.0,
      TRUE ~ sem_gpa
    ))
}

ss_ids <- function() unique(test_student_terms_rp$student_id)

ss_app <- function() tibble::tibble(student_id = ss_ids(), high_school_cum_gpa = 3.0)

ss_opt <- function(...) c(list(classification = "Freshman", min_n = 1L, min_cell_n = 1L, data_edges = rp01_edges),
                          list(...))
