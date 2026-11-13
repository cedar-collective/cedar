# What the tests in test-credit-hours-outside-colors.R share: builders, option lists, constants.

ch_result <- function() {
  credit_hours_by_major(test_students, test_sections, "HIST", hist_major_codes,
                        cedar_report_start_term, cedar_report_end_term,
                        student_terms = ch_student_terms_with_majors)
}
