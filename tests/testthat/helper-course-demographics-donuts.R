# What the tests in test-course-demographics-donuts.R share: builders, option lists, constants.

donut_trace <- function(demo, palette) {
  plots <- plot_demographics_summary(demo, "major_code", color_palette = palette)
  plotly::plotly_build(plots$fall)$x$data[[1]]
}
