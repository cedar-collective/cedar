# What the tests in test-credit-timeline.R share: builders, option lists, constants.

ct_population <- function() {
  tibble::tibble(student_id = c("CT_A", "CT_C"), population_label = "ct")
}

ct_students <- function() {
  # CT_A takes one course per term across their four terms.
  tibble::tibble(
    student_id = rep("CT_A", 4),
    term = c(202080L, 202110L, 202180L, 202210L),
    subject_course = "CTMP 101",
    course_title = "Test Course",
    student_classification = "Freshman",
    registration_status_code = "RE",
    campus = "ABQ"
  )
}
