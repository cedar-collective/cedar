# CC01 (fixtures/scenario_tables.R): students passing 160 attempted credits.

testthat::local_edition(3)

test_that("CC01: who passes the ceiling, where their credits came from and what happens next", {
  r <- get_credit_ceiling_crossings(cc01$student_terms, cc01$programs, cc01$degrees, cc01$opt)
  expect_setequal(r$students$student_id, c("C-A", "C-B", "C-C", "C-D", "C-I"))
  expect_equal(r$by_term$term, c(202180L, 202210L, 202280L))
  expect_equal(r$by_term$n, c(3L, 1L, 1L))
  # Counted, not placed: a record older than the lists, already past, a second degree.
  expect_equal(c(r$meta$n_not_readable, r$meta$n_already_past, r$meta$n_prior_degree), c(1L, 1L, 1L))
  a <- r$students[r$students$student_id == "C-A", ]
  expect_equal(c(a$total, a$elsewhere, a$completed_here, a$not_completed_here), c(165, 120, 36, 9))
  expect_equal(r$students$elsewhere + r$students$completed_here + r$students$not_completed_here, r$students$total)
  # Step 0: C-C's degree that term. Step 1: A and C have degrees, B is enrolled,
  # D is gone, I is past the edge. Step 2: D is past the edge too. Step 3: no one.
  expect_equal(r$outcomes$n_observed, c(5L, 4L, 3L, 0L, 0L))
  expect_equal(r$outcomes$n_degree, c(1L, 2L, 2L, 0L, 0L))
  expect_equal(r$outcomes$n_enrolled, c(4L, 1L, 1L, 0L, 0L))
  expect_equal(r$outcomes$n_gone, c(0L, 1L, 0L, 0L, 0L))

  # The graduate student passes at their own level.
  gr <- get_credit_ceiling_crossings(cc01$student_terms, cc01$programs, cc01$degrees,
                                     utils::modifyList(cc01$opt, list(student_level = "GR")))
  expect_equal(gr$students$student_id, "C-H")
  expect_error(get_credit_ceiling_crossings(cc01$student_terms, cc01$programs, cc01$degrees, list()),
               "settled, graded and degree edges")
  expect_error(get_credit_ceiling_crossings(dplyr::select(cc01$student_terms, -student_level), cc01$programs,
                                            cc01$degrees, cc01$opt), "lacks student_level")
})

test_that("CC01: the page's view of it", {
  r <- get_credit_ceiling_crossings(cc01$student_terms, cc01$programs, cc01$degrees, cc01$opt)
  p <- graduation_ceiling_parts(r)
  expect_equal(p$credits, c(114, 45, 4.8))
  expect_equal(sum(p$share_pct), 100)
  # Under the floor a step is not drawn.
  expect_equal(graduation_ceiling_outcomes(r, min_n = 4L)$step, c(0L, 1L))
  expect_snapshot(cat(format_graduation_ceiling(r), sep = "\n"))
})
