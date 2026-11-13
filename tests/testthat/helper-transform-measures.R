# What the tests in test-transform-measures.R share: builders, option lists, constants.

# The fixtures are already keyed and attached; written as saved tables they
# round-trip, because attach_course_ids() keys again from listed_code and
# attach_default_units() drops the stamped unit columns first. The saved class
# list and schedule also carry Banner's section college (source_college), the
# key the attach reads, which the fixtures never needed: each fixture's own
# college stands in for it.
write_saved_fixtures <- function(dir) {
  qs2::qs_save(dplyr::mutate(test_sections, source_college = college), file.path(dir, "cedar_sections.qs"))
  qs2::qs_save(dplyr::mutate(test_students, source_college = college), file.path(dir, "cedar_registrations.qs"))
  qs2::qs_save(test_degrees, file.path(dir, "cedar_degrees.qs"))
  invisible(dir)
}

# The saved fixtures as the loader (and transform_measures()) holds them:
# units attached from the mapping files and course ids keyed. The fixtures'
# own colleges are not UNM's, so the attached rows carry the files' verdict
# (NA for a college the files do not know), and a table keyed on the college
# has to be compared over these rows, not the fixtures as designed.
loaded_fixtures <- function(students, sections) {
  keyed <- attach_default_units(
    list(cedar_registrations = dplyr::mutate(students, source_college = college),
         cedar_sections = dplyr::mutate(sections, source_college = college)),
    test_dims)
  courses <- build_cedar_courses(keyed$cedar_sections, keyed$cedar_registrations, test_dims)
  attach_course_ids(keyed, courses)
}
