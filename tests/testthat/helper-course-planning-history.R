# What the tests in test-course-planning-history.R share: builders, option lists, constants.

course_history <- function(courses = "SOCI 100", sections = test_sections_regstats,
                           course_terms = test_course_terms_regstats) {
  get_course_planning_history(sections, course_terms, courses, history_edges)
}
