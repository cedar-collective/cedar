# What the tests in test-credit-hours-outside-colors.R share: builders, option lists, constants.

# Home major codes the way Dept Trends resolves them (set_payload's prog_codes).
hist_major_codes <- function() {
  names(major_to_dept)[!is.na(major_to_dept) & major_to_dept == "HIST"]
}

# test_student_terms names no primary major (built without programs), so the
# raw fixture cannot tell a home major from an outside one. Stamp one on the
# student-term table: HIST students sorted by id, first half "HIST-BA" (home),
# second half "BIOL-BS" (outside). Local scaffolding for this contract; the
# shared tables stay unchanged.
ch_student_terms_with_majors <- function() {
  st  <- test_student_terms
  ids <- sort(unique(test_students$student_id[test_students$department == "HIST"]))
  home_ids <- ids[seq_len(ceiling(length(ids) / 2))]
  st$primary_major_code <- dplyr::case_when(
    st$student_id %in% home_ids ~ "HIST-BA",
    st$student_id %in% ids      ~ "BIOL-BS",
    TRUE                        ~ st$primary_major_code
  )
  st
}

ch_result <- function() {
  credit_hours_by_major(test_students, test_sections, "HIST", hist_major_codes(),
                        cedar_report_start_term, cedar_report_end_term,
                        student_terms = ch_student_terms_with_majors())
}
