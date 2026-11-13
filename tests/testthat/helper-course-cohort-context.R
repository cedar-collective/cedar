# What the tests in test-course-cohort-context.R share: builders, option lists, constants.

mc02_context <- function(course = "SPAN 101", ...) {
  build_course_cohort_context(
    test_student_terms_mc, keyed_attempts(test_students_mc, mc02_edges),
    modifyList(list(course = course, classification = "Freshman", college = "ARTS", level = "lower",
                    min_n = 1L, data_edges = mc02_edges), list(...))
  )
}
