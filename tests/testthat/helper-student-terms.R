# What the tests in test-student-terms.R share: builders, option lists, constants.

st01 <- function() build_student_terms(test_students_st, test_programs_st, test_degrees_st)

student_term_row <- function(st, sid, term) {
  r <- st[st$student_id == sid & st$term == term, ]
  if (nrow(r) != 1L) stop("expected one row for ", sid, " ", term, ", got ", nrow(r))
  r
}
