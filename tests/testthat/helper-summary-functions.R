# What the tests in test-summary-functions.R share: builders, option lists, constants.

# Build a minimal downstream signals data frame for testing
make_downstream <- function() {
  tibble::tribble(
    ~source_course, ~dest_course,   ~recent_avg,
    "MATH 1215",    "MATH 1430",    12.3,
    "MATH 1215",    "PHYS 1310",     8.1,
    "HIST 1110",    "HIST 327",      5.4,
    "HIST 1110",    "ANTH 2175",     3.2,
    "ANTH 1140",    "ANTH 2175",     9.0,
  )
}
