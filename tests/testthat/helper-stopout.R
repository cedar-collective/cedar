# What the tests in test-stopout.R share: builders, option lists, constants.

# cedar_attempts as production builds it from a CRN-level class-list fixture:
# the transform's dedup (one row per student, course, campus and term), keyed
# on the course, classified to the graded edge.
fixture_attempts <- function(students, last_graded) {
  rows <- load_transform_helpers()$dedup_class_list_rows(students)
  build_attempts(attach_test_course_ids(rows, "students"), list(last_graded = last_graded))
}
