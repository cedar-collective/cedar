# build_course_cohort_context() and format_course_cohort_context()
# (R/features/course-cohort-context.R): a course's takers-vs-non-takers gap
# read against every course of a college the same population took.
#
# The cone's numbers are tested in test-course-cohort-effect.R; here only the
# feature's own transformations: the wide course rows, which courses enter the
# benchmark, the benchmark summaries, and the words.
#
# MC02 (Freshman; every course is ARTS lower-division) at a settled and graded
# edge of 202110:
#   Spring 2020 ABQ: SPAN 101L is the one course with both a passed and a
#     never-took group (A1, A2 passed; A3, A4 never): gap 0 points on return,
#     +50 on next-term DFW. SPAN 101 itself: everyone passed, no gap.
#   Fall 2020 ABQ: PHIL 105 (A3 passed, did not return; 4 never, 1 returned:
#     -25) and SPAN 201 (A1, A2, G1 passed, none returned; A4 DFW'd and
#     returned; A3 never, did not return: 0) are the benchmark: median -12.5.
# RW01 (Sophomore, ARTS lower-division) with the settled edge moved to 202110
#   so Fall 2020 returns are observable: HIST 1110 and ENGL 1110 each have two
#   passers of whom one returned and never-takers of whom none did: +50 each,
#   so the focal course's gap is above 0% of a one-course benchmark.

library(dplyr)

mc02_edges <- list(last_enrolled = 202180L, last_enrolled_complete = 202110L, last_graded = 202110L)
rw01_settled_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L, last_graded = 202110L)

mc02_context <- function(course = "SPAN 101", ...) {
  build_course_cohort_context(
    test_student_terms_mc, keyed_attempts(test_students_mc, mc02_edges),
    modifyList(list(course = course, classification = "Freshman", college = "ARTS", level = "lower",
                    min_n = 1L, data_edges = mc02_edges), list(...))
  )
}

test_that("MC02: one wide row per course, term and campus; the benchmark is the courses with both groups", {
  p <- mc02_context()
  expect_s3_class(p, "course_cohort_context")
  expect_equal(p$meta$n_benchmark_candidates, 4L)
  expect_equal(sort(unique(p$courses$course)), c("PHIL 105", "SPAN 101", "SPAN 101L", "SPAN 201"))

  lab <- p$courses %>% filter(course == "SPAN 101L", term == 202010L, student_campus == "ABQ")
  expect_true(lab$in_benchmark)
  expect_equal(lab$passed_n_students, 2L)
  expect_equal(lab$none_n_students, 2L)
  expect_equal(lab$lift_return, 0)
  expect_equal(lab$lift_next_dfw, 50)
  # The focal course never benchmarks itself, even with both groups present.
  expect_false(any(p$courses$in_benchmark[p$courses$course == "SPAN 101"]))
  # A course nobody in the population took that term is a row of never-takers.
  phil <- p$courses %>% filter(course == "PHIL 105", term == 202010L, student_campus == "ABQ")
  expect_equal(phil$passed_n_students, 0L)
  expect_equal(phil$none_n_students, 4L)
  expect_false(phil$in_benchmark)

  b <- p$benchmark
  expect_equal(b$term, c(202010L, 202080L))
  expect_equal(b$n_courses, c(1L, 2L))
  expect_equal(b$lift_return_median, c(0, -12.5))
  expect_equal(b$lift_next_dfw_median, c(50, NA))
  # SPAN 101 has no never-took group, so it has no gap to place.
  expect_true(all(is.na(b$share_below_return)))

  f <- p$focal
  expect_equal(f$term, c(202010L, 202010L, 202080L, 202110L))
  expect_equal(f$passed_n_students, c(4L, 2L, 0L, 0L))
  expect_true(all(is.na(f$lift_return)))
  expect_equal(nrow(p$left_out), 0L)
})

test_that("MC02: campus and level scope the benchmark and the population alike", {
  p <- mc02_context(campus = "GA")
  expect_equal(unique(p$courses$student_campus), "GA")
  expect_equal(nrow(p$benchmark), 0L)
  expect_equal(p$population$population, 2L)

  upper <- mc02_context(level = "upper")
  expect_equal(upper$meta$n_benchmark_candidates, 0L)
  expect_equal(unique(upper$courses$course), "SPAN 101")

  # A group under min_n keeps its count and loses its rate, and the course
  # leaves the benchmark: SPAN 201's one DFW and one never-taker against two.
  two <- mc02_context(min_n = 2L)
  s201 <- two$courses %>% filter(course == "SPAN 201", term == 202080L, student_campus == "ABQ")
  expect_equal(c(s201$passed_n_students, s201$dfw_n_students, s201$none_n_students), c(3L, 1L, 1L))
  expect_equal(s201$passed_return_pct, 0)
  expect_true(is.na(s201$dfw_return_pct) && is.na(s201$none_return_pct))
  expect_false(s201$in_benchmark)
  expect_equal(two$benchmark$term, 202010L)
})

test_that("RW01: a focal gap is placed among the benchmark's gaps", {
  st <- suppressMessages(build_student_terms(cedar_registrations_rw, cedar_programs_rw, edges = rw01_settled_edges))
  att <- keyed_attempts(test_students_rw, rw01_settled_edges)
  p <- build_course_cohort_context(st, att, list(
    course = "HIST 1110", classification = "Sophomore", college = "ARTS", level = "lower",
    min_n = 1L, data_edges = rw01_settled_edges, college_label = "Arts"
  ))
  f <- p$focal %>% filter(term == 202080L)
  expect_equal(f$lift_return, 50)
  b <- p$benchmark
  expect_equal(b$term, 202080L)
  expect_equal(b$n_courses, 1L)
  expect_equal(b$lift_return_median, 50)
  expect_equal(b$share_below_return, 0)
  expect_true(is.na(b$share_below_next_dfw))
  expect_equal(p$left_out$n_unclassified, 1L)

  testthat::local_edition(3)
  expect_snapshot(cat(format_course_cohort_context(p), sep = "\n"))
})

test_that("the MC02 words", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_course_cohort_context(mc02_context()), sep = "\n"))
})

test_that("build_course_cohort_context() stops without a focal course, a college, an edge or the columns", {
  att <- keyed_attempts(test_students_mc, mc02_edges)
  expect_error(build_course_cohort_context(test_student_terms_mc, att,
    list(classification = "Freshman", college = "ARTS", data_edges = mc02_edges)), "opt\\$course")
  expect_error(build_course_cohort_context(test_student_terms_mc, att,
    list(course = c("SPAN 101", "PHIL 105"), classification = "Freshman", college = "ARTS",
         data_edges = mc02_edges)), "one focal course")
  expect_error(build_course_cohort_context(test_student_terms_mc, att,
    list(course = "SPAN 101", classification = "Freshman", data_edges = mc02_edges)), "college")
  expect_error(build_course_cohort_context(test_student_terms_mc, att,
    list(course = "SPAN 101", classification = "Freshman", college = "ARTS")), "edge")
  expect_error(build_course_cohort_context(test_student_terms_mc, att %>% select(-level),
    list(course = "SPAN 101", classification = "Freshman", college = "ARTS", data_edges = mc02_edges)), "level")
  expect_error(format_course_cohort_context(list()), "build_course_cohort_context")
})
