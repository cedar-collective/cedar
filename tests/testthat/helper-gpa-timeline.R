# What the tests in test-gpa-timeline.R share: builders, option lists, constants.

gpa_student_terms <- function(students = gpa_students) {
  suppressMessages(build_student_terms(
    students, programs = NULL, degrees = NULL,
    edges = list(last_enrolled_complete = 202180L)
  ))
}

gpa_timeline <- function() build_gpa_timeline(gpa_student_terms())
