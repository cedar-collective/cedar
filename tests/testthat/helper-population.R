# What the tests in test-population.R share: builders, option lists, constants.

# Fixtures here are deliberately local: these tests turn on term spacing relative
# to min/max_data_term, which the shared fixture's stable terms cannot express.
# See the domain-data-vs-input-contract rule in AGENTS.md.
make_population_programs <- function() {
  # S009 row at 202380 anchors min_data_term to a term before S003/S004 (202480),
  # so those students are NOT at the data boundary and correctly get "direct"
  # rather than "unclear". A separate test covers the unclear case.
  tibble(
    student_id         = c("S001", "S002", "S003", "S004", "S005",
                           "S006", "S007", "S007", "S008", "S009"),
    term               = c(202510L, 202510L, 202480L, 202480L, 202510L,
                           202510L, 202510L, 202510L, 202510L, 202380L),
    student_campus     = rep("M", 10),
    student_college    = c("NU", "PO", "NU", "NU", "AS", "NU", "NU", "NU", "AS", "AS"),
    program_type       = c("Major", "Major", "Major", "Major", "Major",
                           "Second Major", "Major", "Major", "Major", "Major"),
    program_name       = c("Nursing", "Public Health", "Nursing", "Nursing",
                           "History", "Nursing", "Nursing", "Nursing", "English",
                           "English"),
    major_code         = c("NURS", "POHE", "FNRS", "FNRS",
                           "HIST", "NURS", "NURS", "FNRS", "ENGL", "ENGL"),
    dept_code          = c("NURS", "POHE", "NURS", "NURS",
                           "HIST", "NURS", "NURS", "NURS", "ENGL", "ENGL"),
    is_pre_major       = c(FALSE, FALSE, TRUE, TRUE,
                           FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
    # S002 and S007 are transfers; rest are native continuing students
    student_population = c("Continuing Student", "Transfer Student",
                           "Continuing Student", "Continuing Student",
                           "Continuing Student", "Continuing Student",
                           "Transfer Student", "Transfer Student",
                           "Continuing Student", "Continuing Student")
  )
}

# Minimal degrees fixture: S001 graduated in term 202510 with a Nursing degree
make_population_degrees <- function() {
  tibble(
    student_id   = "S001",
    term         = 202510L,
    degree       = "BSN",
    program_name = "Nursing",
    major        = "Nursing",
    major_code   = "NURS"
  )
}
