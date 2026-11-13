# What the tests in test-headcount-comprehensive.R share: builders, option lists, constants.

# Two designed students described at the top of test-headcount-comprehensive.R.
PSYCH_MINOR_STUDENT <- "STU-PSYCH-MINOR"
ARCH_CONC_STUDENT   <- "STU-ARCH-CONC"

headcount_plot_xaxes <- function(plot) {
  plot$x$layout[grepl("^xaxis[0-9]*$", names(plot$x$layout))]
}
