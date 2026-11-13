# What the tests in test-registration-snapshots.R share: builders, option lists, constants.

# IS01 and WL01 in one class list, keyed as the loader keys it. The rows are
# tabulated at the top of test-registration-snapshots.R.
snapshot_students <- function() {
  attach_test_course_ids(dplyr::bind_rows(test_students_intersession, test_students_wlmkt), "students")
}

# The course-term table the snapshot reads, built over those rows and IS01's
# schedule as the refresh builds it from one pull.
snapshot_course_terms <- function(students = snapshot_students(), sections = test_sections_intersession) {
  course_terms_for(students, sections)
}
