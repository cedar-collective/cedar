# What the tests in test-course-overview.R share: builders, option lists, constants.

# The base class list carries no CRNs, so it cannot reach a section family
# through the full payload; these tests count its rows directly instead.
base_overview <- function(course) {
  opt <- create_test_opt(list(course = course))
  students <- filter_class_list(test_students, opt)
  assemble_course_overview(
    test_sections,
    add_first_day_enrl(calc_cl_enrls(students), students, test_sections),
    opt
  )
}
