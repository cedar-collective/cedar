# Rollcall donut invariants (Course Dynamics > Rollcall).
#
# Both regressions below shipped and were caught by eye, so they are pinned here:
#   1. The source is keyed by campus/college/subject_course as well as category,
#      so a course taught at two campuses contributed two rows per category.
#      Slicing that ungrouped ranked rows rather than categories, and summing the
#      pre-computed percentage column double-counted — the "Other" slice could
#      exceed 100%.
#   2. The shared colour palette covers only the overall top categories. A term's
#      own top 5 can include one it does not know; those fell through to the same
#      grey used for "Other", making several slices indistinguishable.

context("Course demographics donuts")

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

test_that("donut collapses duplicate category rows instead of ranking them separately", {
  demo <- make_multi_campus_demo()
  tr <- donut_trace(demo, build_color_map(c("HIST", "ANTH", "ENGL")))
  labs <- unlist(tr$labels)

  expect_equal(length(labs), 6)             # top 5 categories + Other
  expect_equal(anyDuplicated(labs), 0)      # a category cannot take two slots
  expect_true("Other" %in% labs)
})

test_that("donut slices account for every student and label to 100%", {
  demo <- make_multi_campus_demo()
  tr <- donut_trace(demo, build_color_map(c("HIST", "ANTH", "ENGL")))
  vals <- unlist(tr$values)

  # Nothing dropped into the remainder and nothing counted twice.
  expect_equal(sum(vals), sum(demo$mean))
  # Labels are derived from the plotted values, so they must total 100.
  expect_lt(abs(sum(round(100 * vals / sum(vals), 1)) - 100), 0.2)
})

test_that("grey is reserved for Other and every other slice is distinct", {
  demo <- make_multi_campus_demo()
  # Palette knows only 3 of the 5 categories that will be plotted.
  tr <- donut_trace(demo, build_color_map(c("HIST", "ANTH", "ENGL")))
  labs <- unlist(tr$labels)
  cols <- tr$marker$colors
  grey <- unname(CEDAR_SEMANTIC_COLORS["other"])

  expect_equal(sum(cols == grey), 1)
  expect_equal(cols[labs == "Other"], grey)
  expect_equal(length(unique(cols)), length(cols))
})

test_that("a category set with no remainder produces no Other slice", {
  demo <- make_multi_campus_demo()
  demo <- demo[demo$major_code %in% c("HIST", "ANTH", "ENGL"), ]
  tr <- donut_trace(demo, build_color_map(c("HIST", "ANTH", "ENGL")))
  labs <- unlist(tr$labels)

  expect_false("Other" %in% labs)
  expect_equal(sum(unlist(tr$values)), sum(demo$mean))
})
