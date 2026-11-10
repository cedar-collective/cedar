# get_course_cohort_effect() (R/cones/course-cohort-effect.R): a course's
# takers against its non-takers, by return and next-term outcomes.
#
# Fixtures (setup.R): the student-term tables built over RP01, MC02 and RW01,
# with each one's attempt table built by keyed_attempts() to the edges below.
#
# RP01, Freshman, ABQ, HIST 499; settled and graded edge 202110:
#   202010 anchors: BACK, DROP, GONE, GRAD, REP passed; FAIL F. (EDROP early
#     dropped and is not enrolled.) Returned: BACK, REP of the passed (2 of 5);
#     FAIL (1 of 1). Next term 202080: BACK HIST 300 A, REP HIST 499 A, DROP's
#     HIST 300 is an early drop (no attempt); FAIL HIST 300 B.
#   202080 anchors: REP passed HIST 499 (returned, HIST 300 A next); BACK,
#     EDROP, FAIL never took it that term (none returned, nothing next).
#   202110 anchor: REP, none; return not observable.
# MC02, Freshman, SPAN 101; settled and graded edge 202110:
#   202010 ABQ: MC_A1..A4 passed, all returned; next term A1 SPAN 201 F, A2 A,
#     A3 PHIL 105 B, A4 B: 4 attempts, 1 DFW.
#   202010 GA: MC_G1, MC_G2 passed; G1 returned (to ABQ), G2 did not; next term
#     G1 SPAN 201 A.
#   202080 ABQ: A1..A4, G1 took no SPAN 101; A1 returned; A1 SPAN 201 A next.
#   202110 ABQ: A1, none; nothing observable.
# RW01, Sophomore, HIST 1110; settled and graded edge 202080, so no return
#   and no next-term outcome is observable:
#   RW_A A and RW_I B passed; RW_C F and RW_D DW (late drop) DFW; RW_H never;
#   RW_B registered with no grade: a taker whose outcome is unknown, left out;
#   RW_F early-dropped and is not enrolled; RW_E is a Junior.

library(dplyr)

rp01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L, last_graded = 202110L)
mc02_edges <- list(last_enrolled = 202180L, last_enrolled_complete = 202110L, last_graded = 202110L)
rw01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202080L, last_graded = 202080L)

test_that("RP01: passed, DFW and never-took groups with their returns and next-term outcomes", {
  res <- get_course_cohort_effect(
    test_student_terms_rp, keyed_attempts(test_students_rp, rp01_edges),
    list(course = "HIST 499", classification = "Freshman", min_n = 1L, data_edges = rp01_edges)
  )
  r <- res$rates
  expect_equal(names(r), c("term", "student_campus", "group", "n_students", "population",
                           "share_of_population", "n_return_observable", "n_returned", "return_pct",
                           "next_term", "next_outcomes_observable", "n_with_next_attempts",
                           "next_attempts", "next_dfw", "next_dfw_pct"))
  expect_equal(r$term,  c(202010L, 202010L, 202080L, 202080L, 202110L))
  expect_equal(r$group, c("passed", "dfw", "passed", "none", "none"))
  expect_equal(r$n_students, c(5L, 1L, 1L, 3L, 1L))
  expect_equal(r$population, c(6L, 6L, 4L, 4L, 1L))
  expect_equal(r$n_returned, c(2L, 1L, 1L, 0L, 0L))
  expect_equal(r$n_return_observable, c(5L, 1L, 1L, 3L, 0L))
  expect_equal(r$return_pct, c(40, 100, 100, 0, NA))
  # DROP's early drop of HIST 300 is not a next-term attempt.
  expect_equal(r$n_with_next_attempts, c(2L, 1L, 1L, 0L, 0L))
  expect_equal(r$next_attempts, c(2L, 1L, 1L, 0L, NA))
  expect_equal(r$next_dfw_pct, c(0, 0, 0, NA, NA))
  expect_equal(r$next_outcomes_observable, c(TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_equal(res$n_population_student_terms, 11L)
  expect_equal(res$n_early_drops, 0L)
  expect_null(res$balance)
})

test_that("MC02: home campus beside the group; a next-term DFW is counted; campus scopes", {
  res <- get_course_cohort_effect(
    test_student_terms_mc, keyed_attempts(test_students_mc, mc02_edges),
    list(course = "SPAN 101", classification = "Freshman", min_n = 1L, data_edges = mc02_edges)
  )
  r <- res$rates
  expect_equal(r$term,           c(202010L, 202010L, 202080L, 202110L))
  expect_equal(r$student_campus, c("ABQ", "GA", "ABQ", "ABQ"))
  expect_equal(r$group,          c("passed", "passed", "none", "none"))
  expect_equal(r$n_students,     c(4L, 2L, 5L, 1L))
  expect_equal(r$return_pct,     c(100, 50, 20, NA))
  expect_equal(r$next_attempts,  c(4L, 1L, 1L, NA))
  expect_equal(r$next_dfw,       c(1L, 0L, 0L, NA))
  expect_equal(r$next_dfw_pct,   c(25, 0, 0, NA))
  expect_equal(r$share_of_population, c(1, 1, 1, 1))

  ga <- get_course_cohort_effect(
    test_student_terms_mc, keyed_attempts(test_students_mc, mc02_edges),
    list(course = "SPAN 101", classification = "Freshman", min_n = 1L, campus = "GA", data_edges = mc02_edges)
  )
  expect_equal(ga$rates$student_campus, "GA")
  expect_equal(ga$rates$n_students, 2L)
})

test_that("MC02: the balance table compares takers with never-takers at their first anchor", {
  res <- get_course_cohort_effect(
    test_student_terms_mc, keyed_attempts(test_students_mc, mc02_edges),
    list(course = "SPAN 101L", classification = "Freshman", min_n = 1L, data_edges = mc02_edges),
    programs = test_programs_mc
  )
  # A1 and A2 took the lab; A3, A4, G1, G2 never did.
  r <- res$rates %>% filter(term == 202010L)
  expect_equal(r$student_campus, c("ABQ", "ABQ", "GA"))
  expect_equal(r$group, c("passed", "none", "none"))
  expect_equal(r$n_students, c(2L, 2L, 2L))
  expect_true(is.data.frame(res$balance$smd_table))
  expect_true(all(res$balance$smd_table$n_treatment <= 2L))
  expect_true(all(res$balance$smd_table$n_control <= 4L))

  expect_error(get_course_cohort_effect(
    test_student_terms_mc, keyed_attempts(test_students_mc, mc02_edges),
    list(course = "SPAN 101", classification = "Freshman", min_n = 1L, term = 202010L, data_edges = mc02_edges),
    programs = test_programs_mc
  ), "never-takers")
})

test_that("RW01: nothing observable gives counts and NA rates; a late drop is DFW; an ungraded taker is left out", {
  res <- get_course_cohort_effect(
    test_student_terms_rw, keyed_attempts(test_students_rw, rw01_edges),
    list(course = "HIST 1110", classification = "Sophomore", min_n = 1L, data_edges = rw01_edges)
  )
  r <- res$rates
  expect_equal(r$term, rep(202080L, 3))
  expect_equal(r$group, c("passed", "dfw", "none"))
  expect_equal(r$n_students, c(2L, 2L, 1L))
  # RW_B, the ungraded taker, is in the population and in no group.
  expect_equal(r$population, rep(6L, 3))
  expect_equal(r$share_of_population, c(2, 2, 1) / 6)
  expect_true(all(is.na(r$return_pct)))
  expect_equal(r$n_return_observable, c(0L, 0L, 0L))
  expect_false(any(r$next_outcomes_observable))
  expect_true(all(is.na(r$next_attempts)))
  expect_equal(res$n_unclassified_takers, 1L)
  expect_equal(res$n_population_student_terms, 6L)

  two <- get_course_cohort_effect(
    test_student_terms_rw, keyed_attempts(test_students_rw, rw01_edges),
    list(course = "HIST 1110", classification = "Sophomore", min_n = 2L, data_edges = rw01_edges)
  )
  expect_equal(two$rates$group, c("passed", "dfw"))
  expect_equal(two$suppressed$group, "none")
  expect_equal(two$rates$population, c(6L, 6L))
})

test_that("get_course_cohort_effect() stops without a course, a classification, an edge or the columns", {
  att <- keyed_attempts(test_students_rp, rp01_edges)
  expect_error(get_course_cohort_effect(test_student_terms_rp, att,
                                        list(classification = "Freshman", data_edges = rp01_edges)), "course")
  expect_error(get_course_cohort_effect(test_student_terms_rp, att,
                                        list(course = "HIST 499", data_edges = rp01_edges)), "classification")
  expect_error(get_course_cohort_effect(test_student_terms_rp, att,
                                        list(course = "HIST 499", classification = "Freshman")),
               "last_enrolled_complete")
  expect_error(get_course_cohort_effect(test_student_terms_rp, att,
                                        list(course = "HIST 499", classification = "Freshman",
                                             data_edges = list(last_enrolled_complete = 202110L))),
               "last_graded")
  expect_error(get_course_cohort_effect(test_student_terms_rp %>% select(-return_observable), att,
                                        list(course = "HIST 499", classification = "Freshman",
                                             data_edges = rp01_edges)), "return_observable")
})
