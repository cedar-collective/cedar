# What the tests in test-course-impact.R share: builders, option lists, constants.

.run_sequence_bands <- function(fixture, ...) {
  suppressMessages(get_course_sequence_effect(
    fixture$students, keyed_attempts(fixture$students, .impact_edges), fixture$programs,
    applicants = fixture$applicants,
    opt = c(list(course_x = "SEQ 101", campus = "ABQ", min_n = 1L), list(...)),
    data_edges = .impact_edges
  ))
}
