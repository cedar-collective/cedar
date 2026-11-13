# What the tests in test-course-attempts.R share: builders, option lists, constants.

# The groups are the student-term table's, never the class list's (ADR-001
# step 5): the loaded class list carries no description, so each designed seat
# gets its classification and primary major from a student-term row built here.
dfw_demo_rows <- function(ids, statuses, grades) {
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)
  dplyr::bind_rows(lapply(seq_along(ids), function(i) {
    base_row %>% dplyr::mutate(
      student_id = ids[[i]], crn = as.character(93000 + i),
      registration_status_code = statuses[[i]], final_grade = grades[[i]]
    )
  }))
}

dfw_demo_terms <- function(rows, classification, major, pre_major = FALSE) {
  tibble::tibble(
    student_id = rows$student_id, term = as.integer(rows$term),
    student_classification = classification,
    primary_major_code = major, is_pre_major = pre_major
  )
}
