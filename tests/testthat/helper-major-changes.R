# What the tests in test-major-changes.R share: builders, option lists, constants.

# The three designed students the detection tests follow, described at the top
# of test-major-changes.R.
CHANGER_A   <- "STU-CHANGER-A"
CHANGER_B   <- "STU-CHANGER-B"
NON_CHANGER <- "STU-NON-CHANGER"

pcc_changes <- function() {
  suppressMessages(detect_major_changes(test_programs_pcc)) %>%
    filter(from_major == "Pre Change Studies")
}

pcc_result <- function(min_n = 1L) {
  suppressMessages(get_pre_change_courses(
    pcc_changes(), test_students_pcc, test_population_pcc,
    opt = list(min_n = min_n)
  ))
}
