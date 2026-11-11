context("Bottleneck: waitlist pressure per campus and term")


# WL02 in the designed fixture; ISSUES.md I16. Matching waitlisted against
# registered rows without the term gave ABQ 1 here: WT_A's Spring seat erased
# their Fall waiting, and WT_B's two terms were pooled into one.
test_that("waitlist pressure is counted per term, on each campus", {
  result <- compute_waitlist_pressure(
    test_students_wlterm,
    population_ids = unique(test_students_wlterm$student_id)
  )

  expect_identical(names(result), c("campus", "term", "subject_course", "n_waitlisted"))
  expect_equal(result$subject_course, rep("PSYC 1110", 3))
  expect_equal(result$campus, c("ABQ", "ABQ", "EA"))
  expect_equal(result$term, c(202080L, 202110L, 202110L))
  expect_equal(result$n_waitlisted, c(2L, 1L, 1L))

  # It is the canonical count, not a second definition of waiting.
  canonical <- summarize_waitlist_demand(
    get_true_waitlisted_rows(test_students_wlterm),
    c("campus", "term", "subject_course"))
  expect_equal(sum(result$n_waitlisted), sum(canonical$waiting))
})


test_that("get_bottlenecks scopes the count to the population and its labels", {
  population <- tibble::tibble(
    student_id = c("WT_A", "WT_B", "WT_D"),
    population_label = c("major", "pre-major", "pre-major")
  )
  result <- get_bottlenecks(population, test_students_wlterm)

  expect_equal(result$population_size, c(major = 1L, `pre-major` = 2L))
  expect_equal(result$waitlist$n_waitlisted, c(2L, 1L, 1L))
  by_label <- result$by_label
  expect_identical(names(by_label),
                   c("population_label", "campus", "term", "subject_course", "n_waitlisted"))
  expect_equal(by_label$population_label, c("major", "pre-major", "pre-major", "pre-major"))
  expect_equal(by_label$term[by_label$population_label == "major"], 202080L)

  # A term scope keeps only that term's waiting.
  spring <- get_bottlenecks(population, test_students_wlterm, opt = list(term = 202110L))
  expect_equal(spring$waitlist$term, c(202110L, 202110L))
  # Options passed in the sections position are refused, not ignored.
  expect_error(get_bottlenecks(population, test_students_wlterm, list(term = 202110L)),
               "pass options by name")
})


test_that("waitlist pressure requires a delivery-campus column", {
  expect_error(
    compute_waitlist_pressure(dplyr::select(test_students_wlterm, -campus), "WT_A"),
    "campus"
  )
})
