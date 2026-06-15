context("Course Flow Branch")

test_that("next-course pairs are campus-scoped and campus-filterable", {
  pairs_all <- get_next_course_pairs(
    test_students,
    opt = list(summer = FALSE)
  )

  expect_true("campus" %in% names(pairs_all))
  expect_true("source_course" %in% names(pairs_all))
  expect_true("dest_course" %in% names(pairs_all))
  expect_true(nrow(pairs_all) > 0)

  campus_scope <- pairs_all$campus[[1]]
  source_course <- pairs_all$source_course[[1]]
  pairs_scoped <- get_next_course_pairs(
    test_students,
    opt = list(course = source_course, campus = campus_scope, summer = FALSE)
  )

  expect_true(nrow(pairs_scoped) > 0)
  expect_setequal(unique(pairs_scoped$campus), campus_scope)
})

test_that("destination and feeder summaries retain campus grouping", {
  pairs <- get_next_course_pairs(test_students, opt = list(summer = FALSE))
  source_course <- pairs$source_course[[1]]
  target_course <- pairs$dest_course[[1]]

  destinations <- get_course_destinations(
    test_students,
    opt = list(course = source_course, summer = FALSE)
  )
  feeders <- get_course_feeders(
    test_students,
    opt = list(course = target_course, summer = FALSE)
  )

  expect_true("campus" %in% names(destinations))
  expect_true("campus" %in% names(feeders))
  expect_false(any(is.na(destinations$campus)))
  expect_false(any(is.na(feeders$campus)))
})

test_that("concurrent course summaries keep student classification", {
  base_row <- test_students %>%
    dplyr::arrange(student_id, term, subject_course) %>%
    dplyr::slice(1)
  source_course <- base_row$subject_course[[1]]
  campus_scope <- base_row$campus[[1]]
  companion_row <- base_row %>%
    dplyr::mutate(
      subject_course = "TEST 999",
      subject_code = "TEST",
      course_title = "Concurrent Fixture Course"
    )
  students_with_concurrent <- dplyr::bind_rows(test_students, companion_row)

  concurrent <- get_concurrent_courses(
    students_with_concurrent,
    opt = list(course = source_course, campus = campus_scope)
  )

  expect_true("student_classification" %in% names(concurrent))
  expect_true(nrow(concurrent) > 0)
  expect_true("TEST 999" %in% concurrent$subject_course)
  expect_true(base_row$student_classification[[1]] %in% concurrent$student_classification)
})

test_that("old course-neighbor function names are intentionally unavailable", {
  expect_false(exists("where_to", mode = "function"))
  expect_false(exists("where_from", mode = "function"))
  expect_false(exists("where_at", mode = "function"))
  expect_false(exists("get_course_neighbors", mode = "function"))
})

test_that("course report flow tab returns sankey plots from branch outputs", {
  pairs <- get_next_course_pairs(test_students, opt = list(summer = FALSE))
  source_course <- pairs$source_course[[1]]
  campus_scope <- pairs$campus[[1]]
  old_base <- cedar_base_dir
  tmp_base <- tempfile("cedar-course-flow-cache-")
  dir.create(file.path(tmp_base, "data"), recursive = TRUE)
  assign("cedar_base_dir", tmp_base, envir = .GlobalEnv)
  on.exit(assign("cedar_base_dir", old_base, envir = .GlobalEnv), add = TRUE)

  plots <- compute_cr_flows_tab(
    base = list(
      opt = list(
        course = source_course,
        course_campus = campus_scope
      )
    ),
    data_objects = list(
      cedar_students = test_students,
      cedar_sections = test_sections
    ),
    min_contrib = 1,
    max_courses = 6
  )

  expect_true(length(plots) > 0)
  expect_true(all(grepl("^sankey_.*_plot$", names(plots))))
})
