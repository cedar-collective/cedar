# Course Dynamics > Retention persistence plot rendering contract.

context("Course Dynamics persistence plot")

test_that("persistence plot uses full horizontal bars and semantic CEDAR colors", {
  persistence <- tibble::tibble(
    campus = rep(c("ABQ", "EA"), each = 4),
    outcome = rep(c("early drop", "late drop", "fail", "pass"), 2),
    n_students = c(20L, 18L, 25L, 80L, 12L, 10L, 15L, 40L),
    n_returned = c(12L, 9L, 10L, 64L, 6L, 4L, 9L, 30L),
    pct_returned = c(0.6, 0.5, 0.4, 0.8, 0.5, 0.4, 0.6, 0.75)
  )

  plot <- build_course_persistence_plot(persistence)
  built <- plotly::plotly_build(plot)
  trace <- built$x$data[[1]]

  expect_s3_class(plot, "plotly")
  expect_identical(trace$type, "bar")
  expect_identical(trace$orientation, "h")
  expect_length(unique(as.character(trace$y)), nrow(persistence))
  expect_setequal(
    unname(unlist(trace$marker$color)),
    unname(CEDAR_COLORS[c("blue", "amber", "red", "green")])
  )
  expect_identical(built$x$layout$plot_bgcolor, "#FFFFFF")
})

test_that("single-campus persistence labels do not repeat the campus", {
  persistence <- tibble::tibble(
    campus = "ABQ",
    outcome = c("fail", "pass"),
    n_students = c(20L, 80L),
    n_returned = c(8L, 64L),
    pct_returned = c(0.4, 0.8)
  )

  trace <- build_course_persistence_plot(persistence) %>%
    plotly::plotly_build() %>%
    purrr::pluck("x", "data", 1)

  expect_setequal(as.character(trace$y), c("Fail", "Pass"))
})

test_that("persistence plot fails closed for incomplete data", {
  expect_null(build_course_persistence_plot(NULL))
  expect_null(build_course_persistence_plot(tibble::tibble()))
  expect_null(build_course_persistence_plot(tibble::tibble(outcome = "pass")))
})
