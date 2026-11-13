# What the tests in test-headcount-comprehensive.R share: builders, option lists, constants.

# Two designed students described at the top of test-headcount-comprehensive.R.
PSYCH_MINOR_STUDENT <- "STU-PSYCH-MINOR"
ARCH_CONC_STUDENT   <- "STU-ARCH-CONC"

headcount_plot_xaxes <- function(plot) {
  plot$x$layout[grepl("^xaxis[0-9]*$", names(plot$x$layout))]
}

# test_dims with the fixtures' own college names: the fixtures' student_college
# values (ARTS, STEM, ...) are not the institution's, so colleges.csv is
# replaced by the codes the Headcount URL uses for them. Units are test_dims'.
headcount_fixture_dims <- function() {
  dims <- test_dims
  dims$colleges <- tibble::tibble(
    college_code = c("AS", "SC", "SO", "ED", "NR", "AD"),
    college_name = c("ARTS", "STEM", "SOSC", "EDU", "NURS", "BUS"),
    source_names = ""
  )
  validate_cedar_dims(dims)
}
