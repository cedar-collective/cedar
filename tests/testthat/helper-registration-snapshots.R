# What the tests in test-registration-snapshots.R share: builders, option lists, constants.

# The course-term table the snapshot reads, built over those rows and IS01's
# schedule as the refresh builds it from one pull.
snapshot_course_terms <- function(students = snapshot_students, sections = test_sections_intersession) {
  course_terms_for(students, sections)
}
