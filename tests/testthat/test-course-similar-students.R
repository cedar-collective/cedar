# get_course_similar_students() (R/cones/course-similar-students.R) and its
# payload (R/features/course-similar-students.R): a course's takers against
# non-takers of the same term, home campus, high-school GPA band and time
# status.
#
# Fixture: RP01 (setup.R), Freshman, ABQ, settled and graded edge 202110.
#   202010 anchors (enrolled): BACK, DROP, FAIL, GONE, GRAD, REP, all with a
#     HIST 499 attempt; EDROP early-dropped it and is not enrolled. Returned
#     in 202080: BACK, FAIL, REP.
#   202080 anchors: REP passed HIST 499 and returned; BACK, EDROP, FAIL passed
#     HIST 300 and did not return; DROP is not enrolled.
# Local frames, built in helper-course-similar-students.R because RP01 has no
# second course in a term, no semester GPA and one time status:
#   `ss_attempts2()` adds HIST 101: 202010 BACK pass (RP_I1), FAIL pass (RP_I3);
#     202080 REP dfw, BACK pass, FAIL dfw.
#   `ss_student_terms2()` sets the 202080 semester GPAs BACK 3.0, FAIL 2.0, REP 4.0.
#   Every student has a high-school GPA of 3.0 unless a test says otherwise.
#
# HIST 101 in 202010 (takers BACK, FAIL; non-takers DROP, GONE, GRAD, REP):
#   return 2 of 2 against the non-takers' 1 of 4; next-term GPA 2.50 against
#   REP's 4.00; other courses that term: 2 HIST 499 attempts, 1 DFW (FAIL's
#   F), against the non-takers' 4 attempts, 0 DFW.
# HIST 499 in 202080 (taker REP; non-takers BACK, EDROP, FAIL):
#   REP's other attempt is HIST 101, a DFW: 1 of 1, against the non-takers'
#   5 attempts (3 HIST 300, 2 HIST 101) with 1 DFW.

test_that("takers are read against the non-takers of their cell: return, other-course DFW, next-term GPA", {
  res <- get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(course = "HIST 101", term = 202010L))
  expect_equal(names(res), c("course", "n_takers", "n_covered", "n_terms",
                             "return_n", "return_pct", "return_expected_pct", "return_gap", "return_gap_se",
                             "other_attempts", "other_dfw_pct", "other_dfw_expected_pct", "other_dfw_gap",
                             "next_gpa_n", "next_gpa", "next_gpa_expected", "next_gpa_gap"))
  expect_equal(res$course, "HIST 101")
  expect_equal(res$n_takers, 2L)
  expect_equal(res$n_covered, 2L)
  expect_equal(res$return_n, 2L)
  expect_equal(res$return_pct, 100)
  expect_equal(res$return_expected_pct, 25)
  expect_equal(res$return_gap, 75)
  expect_equal(res$return_gap_se, 100 * sqrt(2 * 0.25 * 0.75) / 2)
  expect_equal(res$next_gpa_n, 2L)
  expect_equal(res$next_gpa, 2.5)
  expect_equal(res$next_gpa_expected, 4)
  expect_equal(res$other_attempts, 2L)
  expect_equal(res$other_dfw_pct, 50)
  expect_equal(res$other_dfw_expected_pct, 0)
  expect_equal(res$other_dfw_gap, 50)
  expect_equal(attr(res, "edge"), 202110L)
  expect_equal(attr(res, "cells"), c("term", "student_campus", "hs_gpa_band", "time_status"))
})

test_that("a taker's other-course DFW leaves the course itself out, and the non-takers' rate is theirs alone", {
  res <- get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(course = "HIST 499", term = 202080L))
  expect_equal(res$n_takers, 1L)
  expect_equal(res$other_attempts, 1L)
  expect_equal(res$other_dfw_pct, 100)
  expect_equal(res$other_dfw_expected_pct, 20)
  expect_equal(res$return_pct, 100)
  expect_equal(res$return_expected_pct, 0)
  # Next term 202110: only REP has a row, and no non-taker has a GPA to give.
  expect_true(is.na(res$next_gpa_gap))
})

test_that("the high-school GPA band and time status are cells: a taker with no peer in the cell is not covered", {
  # HIST 300 in 202080: takers BACK, EDROP, FAIL; the one non-taker is REP.
  one_band <- get_course_similar_students(ss_student_terms2(), ss_attempts(), ss_app(), ss_opt(course = "HIST 300", term = 202080L))
  expect_equal(one_band$n_covered, 3L)
  # REP and BACK in one band, EDROP and FAIL in another with no non-taker.
  banded <- ss_app() %>% mutate(high_school_cum_gpa = if_else(student_id %in% c("RP_EDROP", "RP_FAIL"), 2.0, 3.0))
  res <- get_course_similar_students(ss_student_terms2(), ss_attempts(), banded, ss_opt(course = "HIST 300", term = 202080L))
  expect_equal(res$n_takers, 3L)
  expect_equal(res$n_covered, 1L)
  expect_equal(res$return_n, 1L)
  expect_equal(res$return_expected_pct, 100)
  # A missing GPA is its own band, not a dropped student.
  no_gpa <- ss_app() %>% mutate(high_school_cum_gpa = if_else(student_id %in% c("RP_REP", "RP_BACK"), NA_real_, 3.0))
  expect_equal(get_course_similar_students(ss_student_terms2(), ss_attempts(), no_gpa,
                                           ss_opt(course = "HIST 300", term = 202080L))$n_covered, 1L)
  # Time status splits the same way.
  part <- ss_student_terms2() %>% mutate(time_status = if_else(student_id == "RP_REP", "Full time", "Part time"))
  split <- get_course_similar_students(part, ss_attempts(), ss_app(), ss_opt(course = "HIST 300", term = 202080L))
  expect_equal(nrow(split), 0L)
  expect_equal(attr(split, "suppressed")$n_covered, 0L)
  # The cell guard: one non-taker is under min_cell_n = 2.
  guarded <- get_course_similar_students(ss_student_terms2(), ss_attempts(), ss_app(),
                                         ss_opt(course = "HIST 300", term = 202080L, min_cell_n = 2L)[-3])
  expect_equal(nrow(guarded), 0L)
})

test_that("every course is a row when none is named, and the instructor grain splits a course's takers", {
  all_courses <- get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(term = 202010L))
  # HIST 499 has no non-taker in 202010 (every member has a row in it).
  expect_equal(all_courses$course, "HIST 101")
  expect_equal(attr(all_courses, "suppressed")$course, "HIST 499")

  by_instructor <- get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(),
                                               ss_opt(course = "HIST 101", term = 202010L, grain = "instructor"))
  expect_equal(sort(by_instructor$instructor_id), c("RP_I1", "RP_I3"))
  expect_equal(by_instructor$n_takers, c(1L, 1L))
  expect_equal(by_instructor$return_expected_pct, c(25, 25))
  gpas <- by_instructor$next_gpa[order(by_instructor$instructor_id)]
  expect_equal(gpas, c(3, 2))
})

test_that("by_term gives the same comparison one anchor term at a time, and the trend reads it", {
  by_term <- get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(course = "HIST 101", by_term = TRUE))
  expect_equal(by_term$term, c(202010L, 202080L))
  expect_equal(by_term$n_takers, c(2L, 3L))
  # 202010 as the pooled single-term row; 202080: REP returned of three,
  # against EDROP, the one non-taker, who did not.
  expect_equal(by_term$return_pct, c(100, 100 / 3))
  expect_equal(by_term$return_expected_pct, c(25, 0))
  # Two terms are not a trend.
  expect_null(course_similar_students_trend(by_term))

  # A local series of per-term gaps: the slope against its own standard error.
  series <- function(gaps, se) tibble::tibble(term = c(202080L, 202110L, 202180L, 202210L, 202260L),
                                               return_gap = gaps, return_gap_se = se)
  up <- course_similar_students_trend(series(c(0, 2, 4, 6, 99), 0.5))
  # The summer term (202260) is left out: four regular terms, +2 a term.
  expect_equal(up$n_terms, 4L)
  expect_equal(up$slope, 2)
  expect_equal(up$slope_se, sqrt(5 * 0.25) / 5)
  expect_equal(up$direction, "improving")
  expect_equal(up$last_term, 202210L)
  expect_equal(course_similar_students_trend(series(c(6, 4, 2, 0, 0), 0.5))$direction, "declining")
  expect_equal(course_similar_students_trend(series(c(0, 2, 4, 6, 0), 5))$direction, "steady")
})

test_that("get_course_similar_students() stops without its inputs", {
  expect_error(get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), list(data_edges = rp01_edges)), "classification")
  expect_error(get_course_similar_students(ss_student_terms2(), ss_attempts2(), NULL, ss_opt()), "applicants")
  expect_error(get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), list(classification = "Freshman")),
               "last_enrolled_complete")
  expect_error(get_course_similar_students(ss_student_terms2() %>% select(-time_status), ss_attempts2(), ss_app(), ss_opt()), "time_status")
  expect_error(get_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(grain = "section")), "grain")
})

test_that("the payload carries the focal row, the benchmark and the instructors; the text preview reads it", {
  payload <- build_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(course = "HIST 101"))
  expect_s3_class(payload, "course_similar_students")
  expect_equal(payload$focal$course, "HIST 101")
  expect_true(all(c("HIST 101", "HIST 499", "HIST 300") %in% payload$courses$course))
  expect_equal(sum(payload$courses$is_focal), 1L)
  expect_equal(payload$benchmark$outcome, c("return", "other_dfw", "next_gpa"))
  expect_equal(payload$benchmark$n_courses[1], nrow(payload$courses) - 1L)
  expect_equal(payload$benchmark$focal_gap[1], payload$focal$return_gap)
  expect_equal(sort(payload$instructors$instructor_id), c("RP_I1", "RP_I3"))
  testthat::local_edition(3)
  expect_snapshot(cat(format_course_similar_students(payload), sep = "\n"))

  # A focal course under the guard has no row and says so.
  thin <- build_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt(course = "HIST 101", min_n = 50L)[-2])
  expect_null(thin$focal)
  expect_snapshot(cat(course_similar_students_headline(thin), sep = "\n"))
  expect_error(build_course_similar_students(ss_student_terms2(), ss_attempts2(), ss_app(), ss_opt()), "focal course")
  expect_error(course_similar_students_headline(list()), "build_course_similar_students")
})
