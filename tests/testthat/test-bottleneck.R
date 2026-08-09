context("Bottleneck: campus-aware waitlist pressure")


test_that("waitlist pressure separates the same course by campus", {
  waitlisted <- gen_ed_assoc_students %>%
    dplyr::distinct(student_id, campus, subject_course) %>%
    dplyr::mutate(registration_status_code = "WL")

  result <- compute_waitlist_pressure(
    waitlisted,
    population_ids = unique(waitlisted$student_id)
  )

  expect_setequal(result$campus, c("ABQ", "EA"))
  expect_equal(result$subject_course, rep("HIST 1110", 2))
  expect_equal(sort(result$n_waitlisted), c(5L, 5L))
})


test_that("waitlist pressure requires a delivery-campus column", {
  waitlisted <- gen_ed_assoc_students %>%
    dplyr::distinct(student_id, subject_course) %>%
    dplyr::mutate(registration_status_code = "WL")

  expect_error(
    compute_waitlist_pressure(waitlisted, unique(waitlisted$student_id)),
    "campus"
  )
})
