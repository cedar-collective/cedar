# What the tests in test-course-planning-history.R share: builders, option lists, constants.

course_history <- function(courses = "SOCI 100", sections = test_sections_regstats,
                           course_terms = test_course_terms_regstats) {
  get_course_planning_history(sections, course_terms, courses, history_edges)
}

course_history_terms <- function() course_terms_for(test_students_course_history, test_sections_course_history)

pending_session_terms <- function() course_terms_for(test_students_pending_session, test_sections_pending_session)

# Catalog membership is analytical scaffolding over EC-11's recorded histories.
planning_gen_ed <- function() data.frame(subject_course = c("SOCI 100", "SOCI 101", "SOCI 104"),
  area_label = c("4: Social sciences", "4: Social sciences", "5: Humanities"))
