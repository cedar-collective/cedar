# What the tests in test-course-demographics-donuts.R share: builders, option lists, constants.

# Same category at two campuses, and a percentage column deliberately
# inconsistent with the headcounts — both true of the real source.
make_multi_campus_demo <- function() {
  majors <- c("HIST", "ANTH", "ENGL", "PSYC", "BIOL", "MATH", "CHEM", "ECON", "SOCI")
  demo <- expand.grid(major_code = majors, campus = c("ABQ", "EA"),
                      stringsAsFactors = FALSE)
  demo$college        <- "AS"
  demo$subject_course <- "HIST 1105"
  demo$term_type      <- "fall"
  demo$mean           <- c(40, 30, 20, 15, 10, 5, 4, 3, 2,
                           20, 15, 10,  8,  5, 3, 2, 1, 1)
  demo$term_type_pct  <- round(100 * demo$mean / sum(demo$mean[demo$campus == "ABQ"]), 1)
  demo
}

donut_trace <- function(demo, palette) {
  plots <- plot_demographics_summary(demo, "major_code", color_palette = palette)
  plotly::plotly_build(plots$fall)$x$data[[1]]
}
