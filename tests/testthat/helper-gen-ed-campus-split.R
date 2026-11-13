# What the tests in test-gen-ed-campus-split.R share: builders, option lists, constants.

ge_profile <- function(min_n = 1L, instructor = TRUE) {
  suppressMessages(get_gen_ed_profile(
    test_students, test_attempts, test_sections, test_programs, NULL, test_student_terms, test_dims,
    list(min_n = min_n,
         include_instructor_dfw = instructor,
         include_associations = FALSE,
         data_edges = data_objects$cedar_edges)
  ))
}

# MC01 in designed_test_data.R mirrors the ABQ gen_ed_assoc rows onto EA: same
# course, same instructors, different students, opposite outcomes. The
# two-campus tests read that fixture rather than building tibbles.
ge_two_campus_profile <- function(min_n = 1L) {
  suppressMessages(get_gen_ed_profile(
    gen_ed_assoc_students,
    gen_ed_assoc_attempts,
    gen_ed_assoc_sections,
    gen_ed_assoc_programs,
    student_terms = test_student_terms_gen_ed_assoc,
    dims = test_dims,
    opt = list(data_edges = data_objects$cedar_edges, dept_code = "HIST", min_n = min_n, include_instructor_dfw = TRUE)
  ))
}
