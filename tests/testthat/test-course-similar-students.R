# get_course_similar_students() (R/cones/course-similar-students.R) and its
# payload (R/features/course-similar-students.R): a course's takers against
# non-takers of the same term, home campus, high-school GPA band and time
# status and, when asked, Pell eligibility, first-generation status and
# credits already earned.
#
# Fixture: RP01 (setup.R), Freshman, ABQ, settled and graded edge 202110.
#   202010 anchors (enrolled): BACK, DROP, FAIL, GONE, GRAD, REP, all with a
#     HIST 499 attempt; EDROP early-dropped it and is not enrolled. Returned
#     in 202080: BACK, FAIL, REP.
#   202080 anchors: REP passed HIST 499 and returned; BACK, EDROP, FAIL passed
#     HIST 300 and did not return; DROP is not enrolled.
# Fixed tables in fixtures/scenario_tables.R, beside RP01, because RP01 has no
# second course in a term, no semester GPA and one time status:
#   `ss_attempts2` adds HIST 101: 202010 BACK pass (RP_I1), FAIL pass (RP_I3);
#     202080 REP dfw, BACK pass, FAIL dfw.
#   `ss_student_terms2` sets the 202080 semester GPAs BACK 3.0, FAIL 2.0, REP 4.0.
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
  res <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(course = "HIST 101", term = 202010L))
  expect_equal(names(res), c("course", "n_takers", "n_covered", "n_terms",
                             "return_n", "return_pct", "return_expected_pct", "return_gap", "return_gap_se",
                             "other_attempts", "other_dfw_pct", "other_dfw_expected_pct", "other_dfw_gap",
                             "other_dfw_gap_se", "next_gpa_n", "next_gpa", "next_gpa_expected", "next_gpa_gap",
                             "next_gpa_gap_se", "act_n", "act", "act_expected", "act_gap", "act_gap_se",
                             "act_gap_smd"))
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

test_that("Pell eligibility and first-generation status are cells when the declarations are given", {
  # `ss_aid`: BACK's only peer is GONE (did not return); FAIL's are DROP, GRAD
  # and REP, of whom REP returned. Expected return (0 + 1/3) / 2.
  res <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                     ss_opt(course = "HIST 101", term = 202010L), programs = ss_aid)
  expect_equal(attr(res, "cells"), c("term", "student_campus", "hs_gpa_band", "time_status", "pell", "first_gen"))
  expect_equal(res$n_covered, 2L)
  expect_equal(res$return_pct, 100)
  expect_equal(res$return_expected_pct, 100 / 6)
  # A student-term the declarations do not describe is its own cell: with
  # GONE's row gone, BACK has no peer and is not covered.
  res <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                     ss_opt(course = "HIST 101", term = 202010L),
                                     programs = ss_aid %>% filter(student_id != "RP_GONE"))
  expect_equal(res$n_takers, 2L)
  expect_equal(res$n_covered, 1L)
  expect_equal(student_term_aid(ss_aid) %>% filter(student_id == "RP_REP") %>% pull(pell), "no")
  expect_error(student_term_aid(ss_aid %>% select(-first_gen)), "first_gen")
  # `ss_aid_mixed`: one row per student-term; a yes beside a no is a yes, a
  # no beside a blank is a no, and a term that records nothing has no label.
  aid <- student_term_aid(ss_aid_mixed)
  expect_equal(nrow(aid), 6L)
  expect_equal(aid$pell[match(c("RP_REP", "RP_DROP", "RP_FAIL"), aid$student_id)], c("yes", NA, "no"))
  expect_equal(aid$first_gen[match(c("RP_REP", "RP_DROP"), aid$student_id)], c("no", "no"))
})

test_that("a member's course is counted from its classified attempts, under the classified attempt's instructor", {
  # `ss_attempts_unclassified`: FAIL's HIST 101 row is an ungraded
  # registration, so FAIL is neither a taker nor a non-taker; BACK's has a
  # second, ungraded row under RP_I9. One taker, read against DROP, GONE, GRAD
  # and REP (1 of 4 returned); BACK's other attempt that term is HIST 499.
  res <- get_course_similar_students(ss_student_terms2, ss_attempts_unclassified, ss_app,
                                     ss_opt(course = "HIST 101", term = 202010L))
  expect_equal(res$n_takers, 1L)
  expect_equal(res$return_expected_pct, 25)
  expect_equal(res$other_attempts, 1L)
  by_instructor <- get_course_similar_students(ss_student_terms2, ss_attempts_unclassified, ss_app,
                                               ss_opt(course = "HIST 101", term = 202010L, grain = "instructor"))
  expect_equal(by_instructor$instructor_id, "RP_I1")
  expect_equal(by_instructor$n_takers, 1L)
})

test_that("a comparison prepared once is read for any rows of its own scope, and stops for another", {
  opt <- ss_opt(term = 202010L)
  prepared <- prepare_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, opt, ss_aid)
  # The readings the payload makes of one preparation: every course, every
  # course term by term, one course's instructors.
  by_instructor <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                               c(opt, list(course = "HIST 101", grain = "instructor")),
                                               ss_aid, prepared)
  expect_equal(sort(by_instructor$instructor_id), c("RP_I1", "RP_I3"))
  expect_equal(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, c(opt, list(by_term = TRUE)),
                                           ss_aid, prepared)$term, 202010L)
  expect_equal(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, opt, ss_aid, prepared)$return_expected_pct,
               100 / 6)
  # Prepared for another term, or with other inputs, it is not read.
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(term = 202080L),
                                           ss_aid, prepared), "prepared")
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, opt, NULL, prepared), "prepared")
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                           c(opt, list(match_credits = TRUE)), ss_aid, prepared), "prepared")
})

test_that("credits already earned are a cell on request, and an invalid timeline is its own", {
  # Stated here: BACK, DROP and REP enter 202010 with no credits, the rest with 20.
  credits <- ss_student_terms2 %>%
    mutate(unm_credits_entering = if_else(student_id %in% c("RP_BACK", "RP_DROP", "RP_REP"), 0, 20),
           timeline_valid = TRUE)
  res <- get_course_similar_students(credits, ss_attempts2, ss_app,
                                     ss_opt(course = "HIST 101", term = 202010L, match_credits = TRUE))
  expect_equal(attr(res, "cells"), c("term", "student_campus", "hs_gpa_band", "time_status", "credits_band"))
  # BACK beside DROP and REP (REP returned): 1/2. FAIL beside GONE and GRAD: 0.
  expect_equal(res$return_expected_pct, 25)
  expect_equal(res$next_gpa_expected, 4)
  expect_equal(res$next_gpa_n, 1L)
  broken <- credits %>% mutate(timeline_valid = student_id != "RP_FAIL")
  res <- get_course_similar_students(broken, ss_attempts2, ss_app,
                                     ss_opt(course = "HIST 101", term = 202010L, match_credits = TRUE))
  expect_equal(res$n_covered, 1L)
  expect_error(get_course_similar_students(ss_student_terms2 %>% select(-any_of("timeline_valid")), ss_attempts2, ss_app,
                                           ss_opt(course = "HIST 101", match_credits = TRUE)), "timeline_valid")
})

test_that("a taker's other-course DFW leaves the course itself out, and the non-takers' rate is theirs alone", {
  res <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(course = "HIST 499", term = 202080L))
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
  one_band <- get_course_similar_students(ss_student_terms2, ss_attempts, ss_app, ss_opt(course = "HIST 300", term = 202080L))
  expect_equal(one_band$n_covered, 3L)
  # REP and BACK in one band, EDROP and FAIL in another with no non-taker.
  banded <- ss_app %>% mutate(high_school_cum_gpa = if_else(student_id %in% c("RP_EDROP", "RP_FAIL"), 2.0, 3.0))
  res <- get_course_similar_students(ss_student_terms2, ss_attempts, banded, ss_opt(course = "HIST 300", term = 202080L))
  expect_equal(res$n_takers, 3L)
  expect_equal(res$n_covered, 1L)
  expect_equal(res$return_n, 1L)
  expect_equal(res$return_expected_pct, 100)
  # A missing GPA is its own band, not a dropped student.
  no_gpa <- ss_app %>% mutate(high_school_cum_gpa = if_else(student_id %in% c("RP_REP", "RP_BACK"), NA_real_, 3.0))
  expect_equal(get_course_similar_students(ss_student_terms2, ss_attempts, no_gpa,
                                           ss_opt(course = "HIST 300", term = 202080L))$n_covered, 1L)
  # Time status splits the same way.
  part <- ss_student_terms2 %>% mutate(time_status = if_else(student_id == "RP_REP", "Full time", "Part time"))
  split <- get_course_similar_students(part, ss_attempts, ss_app, ss_opt(course = "HIST 300", term = 202080L))
  expect_equal(nrow(split), 0L)
  expect_equal(attr(split, "suppressed")$n_covered, 0L)
  # The cell guard: one non-taker is under min_cell_n = 2.
  guarded <- get_course_similar_students(ss_student_terms2, ss_attempts, ss_app,
                                         ss_opt(course = "HIST 300", term = 202080L, min_cell_n = 2L)[-3])
  expect_equal(nrow(guarded), 0L)
})

test_that("every course is a row when none is named, and the instructor grain splits a course's takers", {
  all_courses <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(term = 202010L))
  # HIST 499 has no non-taker in 202010 (every member has a row in it).
  expect_equal(all_courses$course, "HIST 101")
  expect_equal(attr(all_courses, "suppressed")$course, "HIST 499")

  by_instructor <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                               ss_opt(course = "HIST 101", term = 202010L, grain = "instructor"))
  expect_equal(sort(by_instructor$instructor_id), c("RP_I1", "RP_I3"))
  expect_equal(by_instructor$n_takers, c(1L, 1L))
  expect_equal(by_instructor$return_expected_pct, c(25, 25))
  gpas <- by_instructor$next_gpa[order(by_instructor$instructor_id)]
  expect_equal(gpas, c(3, 2))
})

test_that("by_term gives the same comparison one anchor term at a time, and the trend reads it", {
  by_term <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(course = "HIST 101", by_term = TRUE))
  expect_equal(by_term$term, c(202010L, 202080L))
  expect_equal(by_term$n_takers, c(2L, 3L))
  # 202010 as the pooled single-term row; 202080: REP returned of three,
  # against EDROP, the one non-taker, who did not.
  expect_equal(by_term$return_pct, c(100, 100 / 3))
  expect_equal(by_term$return_expected_pct, c(25, 0))
  # Two terms are not a trend.
  expect_true(all(course_similar_students_trend(by_term, "fall")$direction == "too_few_terms"))
})

test_that("each course's gaps get a line a year within one term type, judged against chance and scatter", {
  # ss_gap_series (scenario_tables.R): falls 2019-2022; the spring and summer
  # rows are left out of a fall line.
  trends <- course_similar_students_trend(ss_gap_series, "fall")
  ret <- trends %>% filter(outcome == "return") %>% arrange(course)
  expect_equal(ret$course, c("GAP 100", "GAP 200", "GAP 300"))
  expect_equal(ret$n_terms, c(4L, 4L, 4L))
  expect_equal(ret$last_term, rep(202280L, 3))
  expect_equal(ret$slope, c(2, -2, 1.2))
  # Chance: sqrt(sum of x^2 * se^2) / sum of x^2, x = -1.5 .. 1.5 years.
  expect_equal(ret$slope_se[1], sqrt(5 * 0.25) / 5)
  # GAP 300's scatter (28.8 left around the line over 2 spare terms) is the error.
  expect_equal(ret$slope_se[3], sqrt(28.8 / 2 / 5))
  expect_equal(ret$direction, c("rising", "falling", "steady"))
  expect_equal(ret$fit_first[1], 0)
  expect_equal(ret$fit_last[1], 6)
  expect_equal(trends$direction[trends$outcome == "next_gpa"], rep("too_few_terms", 3))
  expect_equal(trends %>% filter(outcome == "other_dfw") %>% arrange(course) %>% pull(direction),
               c("rising", "falling", "steady"))
  # Springs alone: one term a course.
  expect_true(all(course_similar_students_trend(ss_gap_series, "spring")$direction == "too_few_terms"))
  expect_equal(nrow(course_similar_students_trend(ss_gap_series, NA_character_)), 0L)
  expect_error(course_similar_students_trend(ss_gap_series %>% select(-next_gpa_gap_se), "fall"), "next_gpa_gap_se")
  expect_error(compute_rate_trend(ss_gap_series %>% transmute(term, value = return_gap, se = 0)),
               "positive standard error")
})

test_that("comparison_courses keeps only non-takers in those courses; a cell with none leaves its takers uncovered", {
  # HIST 499 in 202080: taker REP; non-takers BACK, EDROP, FAIL, with 5 other
  # attempts and 1 DFW. Only BACK and FAIL took HIST 101 that term: 4
  # attempts (2 HIST 300, 2 HIST 101), FAIL's HIST 101 the 1 DFW.
  every <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                       ss_opt(course = "HIST 499", term = 202080L))
  in_101 <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                        ss_opt(course = "HIST 499", term = 202080L, comparison_courses = "HIST 101"))
  expect_equal(every$other_dfw_expected_pct, 20)
  expect_equal(in_101$other_dfw_expected_pct, 25)
  expect_equal(in_101$n_takers, 1L)
  # Chance at the expected rate over REP's one other attempt: 100 * sqrt(0.2 * 0.8).
  expect_equal(every$other_dfw_gap_se, 100 * sqrt(0.2 * 0.8))
  expect_equal(attr(every, "n_comparison_student_terms"), 4L)
  expect_equal(attr(in_101, "n_comparison_student_terms"), 3L)
  expect_null(attr(every, "comparison_courses"))
  expect_equal(attr(in_101, "comparison_courses"), "HIST 101")

  # Nobody took the comparison course: HIST 300's three takers are counted,
  # none covered, never dropped.
  none <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                      ss_opt(course = "HIST 300", term = 202080L, comparison_courses = "NOPE 100"))
  expect_equal(nrow(none), 0L)
  expect_equal(attr(none, "suppressed")$n_takers, 3L)
  expect_equal(attr(none, "suppressed")$n_covered, 0L)
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                           ss_opt(comparison_courses = character(0))), "at least one course")
})

test_that("the next-term GPA gap's error is the non-takers' own spread of GPAs", {
  # REP's 202010 HIST 499 attempt relisted as HIST 102: its one taker against
  # non-takers BACK and FAIL, who returned with GPAs 3.0 and 2.0 (variance
  # 0.25), and DROP, GONE and GRAD, who did not.
  rep_102 <- ss_attempts2 %>%
    mutate(subject_course = if_else(student_id == "RP_REP" & term == 202010L, "HIST 102", subject_course))
  res <- get_course_similar_students(ss_student_terms2, rep_102, ss_app, ss_opt(course = "HIST 102", term = 202010L))
  expect_equal(res$next_gpa_n, 1L)
  expect_equal(res$next_gpa_expected, 2.5)
  expect_equal(res$next_gpa_gap_se, 0.5)
})

test_that("each outcome's finding says better, worse or the same against chance, the right way round", {
  payload <- build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                           ss_opt(course = "HIST 101", min_term_n = 1L))
  f <- course_similar_students_findings(payload)
  expect_equal(f$outcome, c("return", "other_dfw", "next_gpa"))
  # Return 60% against 10%: +50 points beyond chance (2 x 12.2).
  expect_equal(f$taker[1], 60)
  expect_equal(f$similar[1], 10)
  expect_equal(f$chance[1], 2 * payload$focal$return_gap_se)
  expect_equal(f$verdict[1], "better")
  # Other courses 20% against 0% expected, and next GPA against REP alone:
  # chance is zero, and the gap cannot be judged.
  expect_equal(f$verdict[2:3], c("unclear", "unclear"))

  # Fewer other courses not passed is better: the same gap read both ways,
  # stated on the focal row.
  dfw_up <- payload
  dfw_up$focal$other_dfw_gap <- 10
  dfw_up$focal$other_dfw_gap_se <- 1
  expect_equal(course_similar_students_findings(dfw_up)$verdict[2], "worse")
  dfw_up$focal$other_dfw_gap <- -10
  expect_equal(course_similar_students_findings(dfw_up)$verdict[2], "better")
  dfw_up$focal$other_dfw_gap <- 1
  expect_equal(course_similar_students_findings(dfw_up)$verdict[2], "same")

  # The text holds the findings, and the headline is every part in order.
  txt <- course_similar_students_text(payload)
  expect_equal(length(txt$findings), 3L)
  expect_equal(course_similar_students_headline(payload), unname(unlist(txt)))
  thin <- build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(course = "HIST 101", min_n = 50L)[-2])
  expect_equal(nrow(course_similar_students_findings(thin)), 0L)
})

test_that("the gen_ed comparison reads the Gen Ed list and says whom it compared", {
  # HIST 101 relisted as HIST 1105, a UNM Gen Ed course: the HIST 499 case
  # above, through the named comparison.
  gen_ed_101 <- ss_attempts2 %>%
    mutate(across(c(subject_course, listed_code), ~ if_else(.x == "HIST 101", "HIST 1105", .x)))
  payload <- build_course_similar_students(ss_student_terms2, gen_ed_101, ss_app,
                                           ss_opt(course = "HIST 499", term = 202080L, comparison = "gen_ed"))
  expect_equal(payload$meta$comparison, "gen_ed")
  expect_true("HIST 1105" %in% payload$meta$comparison_courses)
  expect_equal(payload$focal$other_dfw_expected_pct, 25)
  expect_equal(payload$meta$n_comparison_student_terms, 3L)
  testthat::local_edition(3)
  expect_snapshot(cat(course_similar_students_headline(payload), sep = "\n"))

  expect_equal(build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                             ss_opt(course = "HIST 499", term = 202080L))$meta$comparison, "all")
  expect_error(build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                             ss_opt(course = "HIST 499", comparison = "honors")),
               "comparison must be one of")
})

test_that("get_course_similar_students() stops without its inputs", {
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, list(data_edges = rp01_edges)), "classification")
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, NULL, ss_opt()), "applicants")
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, list(classification = "Freshman")),
               "last_enrolled_complete")
  expect_error(get_course_similar_students(ss_student_terms2 %>% select(-time_status), ss_attempts2, ss_app, ss_opt()), "time_status")
  expect_error(get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(grain = "section")), "grain")
})

test_that("the payload carries the focal row, the benchmark and the instructors; the text preview reads it", {
  payload <- build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                           ss_opt(course = "HIST 101", min_term_n = 1L))
  expect_s3_class(payload, "course_similar_students")
  expect_equal(payload$focal$course, "HIST 101")
  expect_true(all(c("HIST 101", "HIST 499", "HIST 300") %in% payload$courses$course))
  expect_equal(sum(payload$courses$is_focal), 1L)
  expect_equal(payload$benchmark$outcome, c("return", "other_dfw", "next_gpa"))
  expect_equal(payload$benchmark$n_courses[1], nrow(payload$courses) - 1L)
  expect_equal(payload$benchmark$focal_gap[1], payload$focal$return_gap)
  expect_equal(sort(payload$instructors$instructor_id), c("RP_I1", "RP_I3"))
  # Every course's terms, the focal one's among them; fall has the most takers.
  expect_equal(payload$by_term, payload$courses_by_term %>% filter(course == "HIST 101"))
  expect_true(all(c("HIST 300", "HIST 499") %in% payload$courses_by_term$course))
  expect_equal(payload$meta$trend_term_type, "fall")
  expect_true(all(c("return_trend", "return_trend_slope", "return_trend_chance", "return_gap_series") %in% names(payload$courses)))
  expect_equal(payload$trend, payload$trends %>% filter(course == "HIST 101"))
  testthat::local_edition(3)
  expect_snapshot(cat(format_course_similar_students(payload), sep = "\n"))

  # A focal course under the guard has no row and says so.
  thin <- build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(course = "HIST 101", min_n = 50L)[-2])
  expect_null(thin$focal)
  expect_snapshot(cat(course_similar_students_headline(thin), sep = "\n"))
  # The lead reads each gap's line: GAP 100's series stands in for the trend.
  trended <- payload
  trended$trend <- course_similar_students_trend(ss_gap_series, "fall") %>% filter(course == "GAP 100")
  expect_snapshot(cat(tail(course_similar_students_headline(trended), 2), sep = "\n"))
  expect_error(build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt()), "focal course")
  expect_error(course_similar_students_headline(list()), "build_course_similar_students")
})

test_that("the alike check reads ACT, which the cells do not hold, the same way as an outcome", {
  # ss_app_act: HIST 101's takers in 202010 average 19 against their
  # non-takers' 24 (22, 24, 26: variance 8/3); REP has no score and is in
  # neither average.
  res <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app_act, ss_opt(course = "HIST 101", term = 202010L))
  expect_equal(res$act_n, 2L)
  expect_equal(res$act, 19)
  expect_equal(res$act_expected, 24)
  expect_equal(res$act_gap, -5)
  expect_equal(res$act_gap_se, sqrt(2 * 8 / 3) / 2)
  expect_equal(res$act_gap_smd, -5 / sqrt(8 / 3))
  # The outcomes do not move with the scores.
  expect_equal(res$return_gap, 75)
  # No score on file anywhere: nothing to check, never zero.
  none <- get_course_similar_students(ss_student_terms2, ss_attempts2, ss_app, ss_opt(course = "HIST 101", term = 202010L))
  expect_equal(none$act_n, 0L)
  expect_true(is.na(none$act_gap))
  # A value outside 1 to 36 is not a score.
  bad <- ss_app_act %>% mutate(unm_act_combined_score = if_else(student_id == "RP_BACK", 0, unm_act_combined_score))
  expect_equal(get_course_similar_students(ss_student_terms2, ss_attempts2, bad,
                                           ss_opt(course = "HIST 101", term = 202010L))$act_n, 1L)
})

test_that("the alike verdict follows the gap in standard deviations", {
  build <- function(app, ...) build_course_similar_students(ss_student_terms2, ss_attempts2, app,
                                                            ss_opt(course = "HIST 101", term = 202010L, ...))
  apart <- course_similar_students_alike(build(ss_app_act))
  expect_equal(apart$status, "apart")
  expect_equal(apart$gap, -5)
  alike <- course_similar_students_alike(build(ss_app_act_alike))
  expect_equal(alike$status, "alike")
  expect_equal(course_similar_students_alike(build(ss_app))$status, "none")
  expect_equal(course_similar_students_alike(build(ss_app))$sentence, character(0))
  # Two takers, one with a score: under a guard of two, too few to check.
  few <- build_course_similar_students(
    ss_student_terms2, ss_attempts2,
    ss_app_act %>% mutate(unm_act_combined_score = if_else(student_id == "RP_FAIL", NA, unm_act_combined_score)),
    ss_opt(course = "HIST 101", term = 202010L, min_n = 2L)[-2])
  expect_equal(course_similar_students_alike(few)$status, "too_few")
  testthat::local_edition(3)
  expect_snapshot(cat(course_similar_students_alike(build(ss_app_act))$sentence,
                      course_similar_students_alike(build(ss_app_act_alike))$sentence,
                      course_similar_students_alike(few)$sentence, sep = "\n"))
})
