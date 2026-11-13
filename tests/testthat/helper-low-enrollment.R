# What the tests in test-low-enrollment.R share: builders, option lists, constants.

rn01_sections <- function() {
  dims <- build_cedar_dims(read_institution_mappings(cedar_institution_dir(cedar_base_dir, "demo")))
  courses <- suppressMessages(build_cedar_courses(test_sections_rn, test_students_rn, dims))
  suppressMessages(attach_course_ids(list(cedar_sections = test_sections_rn), courses))$cedar_sections
}
