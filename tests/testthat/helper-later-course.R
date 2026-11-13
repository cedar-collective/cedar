# What the tests in test-later-course.R do: run the later-course functions on
# DS01 (STAT 145 into STAT 245, ABQ, the default three-term window) and on
# MC02 (SPAN 101 into SPAN 201; its three terms leave room for a two-term
# window). Each takes the options a test changes.

ds_cohort <- function(...) {
  build_downstream_cohort(
    test_students_ds, ds_attempts, "STAT 145", "STAT 245",
    modifyList(list(campus = "ABQ", data_edges = ds01_edges), list(...))
  )$cohort
}

ds_outcomes <- function(...) {
  get_downstream_outcomes(test_students_ds, ds_attempts, modifyList(
    list(course_x = "STAT 145", course_y = "STAT 245", campus = "ABQ", data_edges = ds01_edges),
    list(...)
  ))
}

ds_later_course <- function(...) {
  build_later_course(test_students_ds, ds_attempts, modifyList(
    list(course_x = "STAT 145", course_y = "STAT 245", campus = "ABQ", data_edges = ds01_edges),
    list(...)
  ))
}

ds_balance <- function(...) {
  suppressMessages(get_downstream_instructor_balance(
    test_students_ds, ds_attempts, test_programs_ds, NULL,
    opt = modifyList(
      list(course_x = "STAT 145", course_y = "STAT 245", campus = "ABQ", data_edges = ds01_edges),
      list(...)
    ),
    student_terms = test_student_terms_ds
  ))
}

mc_outcomes <- function(students = test_students_mc, ...) {
  get_downstream_outcomes(students, keyed_attempts(students, .impact_edges), modifyList(
    list(course_x = "SPAN 101", course_y = "SPAN 201", window_terms = 2L, min_n = 1L,
         data_edges = .impact_edges),
    list(...)
  ))
}

mc_options <- function(students = test_students_mc, ...) {
  get_downstream_course_options(
    students, keyed_attempts(students, .impact_edges), "SPAN 101",
    modifyList(list(min_n = 1L, window_terms = 2L, data_edges = .impact_edges), list(...))
  )
}
