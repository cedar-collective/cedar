# get_course_pair_dfw() (R/cones/course-pair-dfw.R): is a course harder for
# students who take another course the same term? PD01 is in
# fixtures/scenario_tables.R.

test_that("PD01: a pair is read within term and entering-GPA band, continuing students only", {
  r <- get_course_pair_dfw(pd01$attempts, pd01$student_terms, list(
    course = "CHEM 121", data_edges = pd01_edges, min_n = 5L, min_term_n = 3L))
  counts <- r$meta$counts
  expect_equal(c(counts$n_graded, counts$n_first_term, counts$n_invalid, counts$n_continuing),
               c(42L, 3L, 3L, 36L))
  # The lab is CHEM 121's own family and is never a pair.
  expect_setequal(r$pairs$other_course, c("MATH 162", "ENGL 220"))

  # MATH 162: 6 of 9 DFW against 3 x (3 x 1/5) = 1.8 expected, worse every fall.
  math <- filter(r$pairs, other_course == "MATH 162")
  expect_equal(c(math$n_student_terms, math$n_terms, math$n_terms_read, math$n_terms_worse), c(9L, 3L, 3L, 3L))
  expect_equal(math$dfw_with_pct, 100 * 6 / 9)
  expect_equal(math$dfw_expected_pct, 20)
  expect_equal(math$z, (6 / 9 - 0.2) / sqrt(0.2 * 0.8 / 9))
  expect_true(math$harder_together)

  # ENGL 220's takers DFW at 50%, as do the rest of their low band: no gap,
  # though they DFW more than CHEM 121's students overall.
  engl <- filter(r$pairs, other_course == "ENGL 220")
  expect_equal(c(engl$dfw_with_pct, engl$dfw_expected_pct, engl$gap_pts), c(50, 50, 0))
  expect_false(engl$harder_together)
  expect_identical(r$pairs$other_course, c("MATH 162", "ENGL 220"))
})

test_that("PD01: a candidate needs its terms, its size and the term type asked for", {
  run <- function(...) get_course_pair_dfw(pd01$attempts, pd01$student_terms, list(
    course = "CHEM 121", data_edges = pd01_edges, min_n = 5L, min_term_n = 3L, ...))$pairs
  # Three falls are not four.
  expect_false(filter(run(min_terms = 4L), other_course == "MATH 162")$harder_together)
  # A pair under min_n is not read, and is counted.
  small <- get_course_pair_dfw(pd01$attempts, pd01$student_terms, list(
    course = "CHEM 121", data_edges = pd01_edges, min_n = 10L, min_term_n = 3L))
  expect_equal(nrow(small$pairs), 0L)
  expect_equal(small$meta$counts$n_pairs_small, 2L)
  # Spring holds none of PD01; the graded edge bounds the terms.
  expect_equal(nrow(run(term_type = "spring")), 0L)
  early <- get_course_pair_dfw(pd01$attempts, pd01$student_terms, list(
    course = "CHEM 121", data_edges = list(last_graded = 202180L), min_n = 5L, min_term_n = 3L))
  expect_equal(early$meta$terms, c(202080L, 202180L))
  expect_error(get_course_pair_dfw(pd01$attempts, pd01$student_terms, list(course = "CHEM 121")),
               "last_graded")
  expect_error(get_course_pair_dfw(select(pd01$attempts, -outcome), pd01$student_terms,
                                   list(course = "CHEM 121", data_edges = pd01_edges)), "outcome")
})
