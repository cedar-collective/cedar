context("Course Flow Branch")

test_that("next-course pairs are campus-scoped and campus-filterable", {
  pairs_all <- get_next_course_pairs(
    test_students,
    opt = list(course = "HIST 1110", summer = FALSE)
  )

  expect_true("campus" %in% names(pairs_all))
  expect_true("source_course" %in% names(pairs_all))
  expect_true("dest_course" %in% names(pairs_all))
  expect_true(nrow(pairs_all) > 0)

  campus_scope <- pairs_all$campus[[1]]
  pairs_scoped <- get_next_course_pairs(
    test_students,
    opt = list(course = "HIST 1110", campus = campus_scope, summer = FALSE)
  )

  expect_true(nrow(pairs_scoped) > 0)
  expect_setequal(unique(pairs_scoped$campus), campus_scope)
})

test_that("destination and feeder summaries retain campus grouping", {
  destinations <- get_course_destinations(
    test_students,
    opt = list(course = "HIST 1110", summer = FALSE)
  )
  feeders <- get_course_feeders(
    test_students,
    opt = list(course = "HIST 1110", summer = FALSE)
  )

  expect_true("campus" %in% names(destinations))
  expect_true("campus" %in% names(feeders))
  expect_false(any(is.na(destinations$campus)))
  expect_false(any(is.na(feeders$campus)))
})

test_that("old course-neighbor function names are intentionally unavailable", {
  expect_false(exists("where_to", mode = "function"))
  expect_false(exists("where_from", mode = "function"))
  expect_false(exists("where_at", mode = "function"))
  expect_false(exists("get_course_neighbors", mode = "function"))
})
