# Course Dynamics > Downstream > Later Course.
#
#   R/branches/downstream-cohort.R          build_downstream_cohort(),
#                                           get_downstream_course_options()
#   R/cones/downstream-outcomes.R           get_downstream_outcomes()
#   R/cones/downstream-instructor-balance.R get_downstream_instructor_balance()
#   R/features/later-course.R               the page's payload, tables and words
#
# DS01 (fixtures/designed_test_data.R) is a course and its sequel built so
# that each rule that once miscounted has a row that breaks if the rule does;
# its header pins every count asserted here. MC02 supplies repeats, a
# co-requisite and a second campus. The failure mode is a plausible number,
# not an error, so these pin arithmetic, denominators and who is counted.

# ── The cohort: window, edges, exclusions ────────────────────────────────────

test_that("a later course taken after the grade edge still counts as taken", {
  # ISSUES I56. DS_E1 takes STAT 245 in Fall 2022: settled, not graded yet.
  # Reading continuation only to the grade edge made them a non-continuer.
  e1 <- dplyr::filter(ds_cohort(), student_id == "DS_E1")
  expect_true(e1$eligible)
  expect_true(e1$took_y)
  expect_equal(e1$y_outcome, "not_graded")
  s <- ds_outcomes()$summary
  expect_equal(c(s$n_eligible, s$n_took_y, s$n_not_graded), c(12L, 9L, 1L))
  expect_equal(s$pct_took_y, 75)
})

test_that("the follow-up window is fixed, and a cohort without it is censored", {
  cohort <- ds_cohort()
  # Four regular terms after X: outside the default three-term window.
  c2 <- dplyr::filter(cohort, student_id == "DS_C2")
  expect_true(c2$eligible)
  expect_false(c2$took_y)
  # Window ends past the settled edge: censored, never a non-continuer.
  r1 <- dplyr::filter(cohort, student_id == "DS_R1")
  expect_true(r1$right_censored)
  expect_false(r1$eligible)

  # A four-term window takes in DS_C2, and censors DS_E1, whose fourth term is
  # past the settled edge.
  wide <- ds_outcomes(window_terms = 4L)$summary
  expect_equal(c(wide$n_right_censored, wide$n_eligible, wide$n_took_y), c(3L, 11L, 9L))

  expect_error(ds_outcomes(window_terms = 0L), "window_terms")
})

test_that("the removals on the page add up to the denominator", {
  # DS_Q1 passed STAT 245 before STAT 145 and is too recent: one student, in
  # both groups. Subtracting both counts would remove them twice.
  r <- ds_later_course()
  for (d in list(r$summary, r$by_grade, r$by_term)) {
    expect_equal(d$n_in_x - d$n_right_censored - d$n_prior_excluded, d$n_eligible)
  }
  expect_equal(c(r$summary$n_passed_y_before_x, r$summary$n_prior_excluded), c(2L, 1L))
  steps <- later_course_headline(r)[[1]]$steps
  expect_equal(steps$n[steps$role == "total"] - sum(steps$n[steps$role == "removed"]),
               steps$n[steps$role == "denominator"])
  # What became of those who took it: passed, DFW, not graded, no outcome.
  expect_equal(sum(steps$n[steps$role %in% c("outcome", "unknown")]),
               steps$n[steps$role == "count"])
})

test_that("a same-term pass is concurrent: counted, never removed", {
  s1 <- dplyr::filter(ds_cohort(), student_id == "DS_S1")
  expect_true(s1$passed_y_same_term)
  expect_false(s1$prior_pass_excluded)
  expect_true(s1$eligible)
  expect_false(s1$took_y)
  expect_equal(ds_outcomes()$summary$n_passed_y_same_term, 1L)
})

test_that("the edges are required and must be the ones the attempts were built to", {
  expect_error(ds_outcomes(data_edges = NULL), "data_edges")
  expect_error(ds_outcomes(data_edges = mc02_edges), "graded")
  expect_error(ds_outcomes(course_y = c("STAT 145", "STAT 245")), "its own later course")
})

# ── The cone's tables ────────────────────────────────────────────────────────

test_that("later outcomes are read by the grade earned in X", {
  g <- ds_outcomes()$by_grade
  band <- function(b) unlist(dplyr::filter(g, x_band == b)[c("n_eligible", "n_took_y", "n_pass")],
                             use.names = FALSE)
  expect_equal(band("A"), c(3L, 3L, 2L))
  expect_equal(band("B"), c(4L, 3L, 1L))
  expect_equal(dplyr::filter(g, x_band == "B")$n_not_graded, 1L)
  expect_equal(band("C"), c(2L, 1L, 0L))
  # DS_F1's first attempt is the F; their later pass does not move their band.
  expect_equal(band("C- to F"), c(2L, 2L, 1L))
  # A late drop in X is a band of its own.
  expect_equal(band("Withdrew"), c(1L, 0L, 0L))
  # The bands partition the cohort.
  expect_equal(c(sum(g$n_in_x), sum(g$n_took_y)), c(15L, 9L))
})

test_that("the per-term series counts each student at the term of their first X", {
  r <- ds_outcomes()
  t <- r$by_term
  expect_equal(t$term_x, c(202080L, 202110L, 202210L))
  expect_equal(t$term_type, c("fall", "spring", "spring"))
  expect_equal(t$n_in_x, c(12L, 1L, 2L))
  expect_equal(t$n_eligible, c(11L, 1L, 0L))
  expect_equal(t$n_took_y, c(8L, 1L, 0L))
  expect_equal(t$n_pass, c(4L, 0L, 0L))
  expect_equal(t$n_dfw, c(4L, 0L, 0L))
  expect_equal(t$n_not_graded, c(0L, 1L, 0L))
  expect_equal(t$n_right_censored, c(0L, 0L, 2L))
  # The terms add back up to the headline, which is counted on its own.
  expect_equal(sum(t$n_took_y), r$summary$n_took_y)
  # Most of the students who could have continued took X in a Fall.
  expect_equal(r$main_term_type, "fall")
})

test_that("timing counts regular terms after X, a summer joining the term after it", {
  t <- ds_outcomes()$timing
  expect_equal(t$gap_terms, 1:3)
  expect_equal(t$n, c(5L, 3L, 1L))
  expect_equal(t$cum_pct_of_eligible, 100 * c(5, 8, 9) / 12)
  # DS_C1: STAT 145 in Fall 2020, STAT 245 in Summer 2021.
  expect_equal(dplyr::filter(ds_cohort(), student_id == "DS_C1")$gap_terms, 2L)
})

test_that("what a student did after X is read on every campus", {
  cohort <- ds_cohort()
  # DS_B2 took X at ABQ and Y at GA: a continuer.
  b2 <- dplyr::filter(cohort, student_id == "DS_B2")
  expect_true(b2$took_y)
  expect_equal(b2$y_outcome, "pass")
  # The cohort itself stays scoped to the campus that delivered X.
  expect_false("DS_G1" %in% cohort$student_id)

  all_campuses <- ds_outcomes(campus = NULL)
  expect_equal(all_campuses$summary$campus, c("ABQ", "GA"))
  expect_equal(all_campuses$summary$n_in_x, c(15L, 1L))
  expect_equal(all_campuses$summary$n_took_y, c(9L, 1L))
  # Every table is split by the campus that delivered X.
  for (name in c("by_grade", "by_term", "timing", "order_by_year")) {
    expect_setequal(all_campuses[[name]]$campus, c("ABQ", "GA"))
  }
})

test_that("a late drop in Y is DFW and is counted as a withdrawal", {
  s <- ds_outcomes()$summary
  expect_equal(c(s$n_pass, s$n_dfw, s$n_withdrew), c(4L, 4L, 1L))   # DS_N1 withdrew
  expect_equal(s$n_graded, 8L)
})

test_that("the instructor breakdown carries each instructor's grade mix in X", {
  r <- ds_outcomes(by_instructor = TRUE)
  of <- function(name) unlist(dplyr::filter(r$instructors, instructor == name)[
    c("n_eligible", "n_took_y", "n_pass", "n_dfw", "n_x_pass", "n_x_a_or_b")], use.names = FALSE)
  expect_equal(of("DS_I1"), c(6L, 4L, 2L, 1L, 5L, 5L))
  expect_equal(of("DS_I2"), c(5L, 4L, 2L, 2L, 3L, 1L))
  # A student whose X section has no recorded instructor still counts.
  expect_equal(of("Instructor not recorded")[1:2], c(1L, 1L))
  # Breakdown rows add back up to the headline, which is counted on its own.
  expect_equal(sum(r$instructors$n_took_y), r$summary$n_took_y)
  # And within a grade band, so "a B from one instructor" can be compared.
  b <- dplyr::filter(r$instructors_by_grade, x_band == "B")
  expect_equal(dplyr::filter(b, instructor == "DS_I1")$n_took_y, 2L)
  expect_equal(dplyr::filter(b, instructor == "DS_I2")$n_pass, 1L)

  # Not asked for, not returned.
  expect_null(ds_outcomes()$instructors)
  expect_null(ds_outcomes()$instructors_by_grade)
})

test_that("a small cell keeps its counts and hides its rates", {
  r <- ds_outcomes(min_n = 5L)
  c_band <- dplyr::filter(r$by_grade, x_band == "C")
  expect_equal(c_band$n_eligible, 2L)
  expect_true(is.na(c_band$pct_took_y))
  expect_true(is.na(c_band$pct_pass))
  # The headline has 12 eligible and 8 graded: both clear the guard.
  expect_equal(c(r$summary$pct_took_y, r$summary$pct_pass), c(75, 50))
  # At the default of 10 the 8 graded do not.
  expect_true(is.na(ds_outcomes()$summary$pct_pass))
})

test_that("grade bands sit on one side of the pass line", {
  banded <- add_attempt_grade_band(grade_band_attempts)
  expect_equal(banded$grade_band, c(
    "A", "A", "B", "C", "C- to F", "C- to F", "C- to F",
    "Other passing", "Other nonpassing", "Other nonpassing", "Withdrew", "Withdrew"
  ))
  expect_setequal(unique(banded$grade_band[banded$outcome %in% "pass"]),
                  c("A", "B", "C", "Other passing"))
  expect_true(all(banded$grade_band %in% GRADE_BAND_LEVELS))
  expect_error(add_attempt_grade_band(dplyr::select(grade_band_attempts, -outcome_category)),
               "outcome_category")
})

test_that("advance_term steps regular terms, summer moving to fall first", {
  expect_equal(advance_term(c(202080L, 202010L, 202060L), 1), c(202110L, 202080L, 202080L))
  expect_equal(advance_term(202080L, 3), 202210L)
})

# ── The later-course picker ──────────────────────────────────────────────────
#
# MC02: SPAN 101 is the gateway, SPAN 101L a co-requisite taken in the SAME
# term (so not a later course), SPAN 201 the later course, PHIL 105 a later
# course in another department. MC_A1 takes SPAN 201 twice.

test_that("the picker and the analysis show the same continuation share", {
  opts <- get_downstream_course_options(
    test_students_ds, ds_attempts, "STAT 145",
    list(campus = "ABQ", min_n = 1L, data_edges = ds01_edges)
  )
  y <- dplyr::filter(opts, subject_course == "STAT 245")
  s <- ds_outcomes()$summary
  expect_equal(c(y$n_students, y$n_eligible), c(s$n_took_y, s$n_eligible))
  expect_equal(y$pct_of_x, s$pct_took_y)
})

test_that("the picker lists only courses taken after X, each student once", {
  o <- mc_options()
  expect_false("SPAN 101" %in% o$subject_course)      # never itself
  expect_false("SPAN 101L" %in% o$subject_course)     # same term, not after
  expect_true(all(c("SPAN 201", "PHIL 105") %in% o$subject_course))
  # Department ownership is kept for the picker's groups and the rollup; it
  # does not establish relevance.
  expect_true(o$same_dept[[1]])
  expect_equal(o$subject_course[[1]], "SPAN 201")
  # MC_A1, MC_A2, MC_A4 and MC_G1 reach it; MC_A3 goes to PHIL 105, MC_G2 stops.
  s201 <- dplyr::filter(o, subject_course == "SPAN 201")
  expect_equal(s201$n_students, 4L)
  expect_equal(s201$pct_of_x, 100 * 4 / 6)

  # A thin later course drops out at min_n.
  expect_equal(mc_options(min_n = 2L)$subject_course, "SPAN 201")
})

test_that("campus scopes the picker to the campuses the analysis will use", {
  # Restricting to ABQ removes MC_G1 and MC_G2 from the SPAN 101 cohort.
  s201 <- dplyr::filter(mc_options(campus = "ABQ"), subject_course == "SPAN 201")
  expect_equal(s201$n_students, 3L)     # MC_A1, MC_A2, MC_A4, not MC_G1
  expect_equal(s201$pct_of_x, 75)       # 3 of the 4 ABQ students
})

test_that("the picker stops at the settled edge and censors recent cohorts", {
  students <- dplyr::bind_rows(
    test_students_mc,
    .mc_row("MC_G2", 202180, "SPAN 201", "GA", "SPAN", grade = NA_character_, instructor = "MC_I2"),
    .mc_row("MC_RECENT", 202110, "SPAN 101", "ABQ", "SPAN", grade = "A", instructor = "MC_I1")
  )
  s201 <- dplyr::filter(mc_options(students), subject_course == "SPAN 201")
  expect_equal(s201$n_students, 4L)            # Fall 2021 is past the settled edge
  expect_equal(s201$pct_of_x, 100 * 4 / 6)     # MC_RECENT has no full window
})

# ── Repeats, co-requisites and campuses, on MC02 ─────────────────────────────

test_that("a co-requisite in a set of later courses does not erase students", {
  # SPAN 101L is taken in the SAME term as SPAN 101. Reducing each student to
  # their earliest enrollment in the set before applying the after-X filter
  # would pick the lab, discard it, and lose a student who took SPAN 201 later.
  r <- mc_outcomes(course_y = c("SPAN 101L", "SPAN 201"))
  expect_true(r$rollup)
  expect_equal(r$course_y_label, "any of 2 later courses")
  # MC_A1, MC_A2, MC_A4 and MC_G1 all reached SPAN 201 after SPAN 101.
  expect_equal(sum(r$summary$n_took_y), 4L)
  # Passing one member of a set does not exclude anyone from the others.
  expect_equal(sum(r$summary$n_eligible), 6L)
  expect_equal(sum(r$summary$n_prior_excluded), 0L)
})

test_that("students are counted, not enrollments, when a course is repeated", {
  # MC_A1 takes SPAN 201 twice: fails in Fall 2020, passes in Spring 2021. One
  # student, read at the first attempt.
  s <- mc_outcomes()$summary
  expect_equal(sum(s$n_took_y), 4L)   # not 5
  expect_equal(sum(s$n_dfw), 1L)

  # And when X is repeated, the student is still one row of the cohort.
  repeated_x <- test_students_mc %>%
    dplyr::filter(student_id == "MC_A1", subject_course == "SPAN 101") %>%
    dplyr::mutate(enrollment_id = paste0(enrollment_id, "-REPEAT"),
                  section_id = paste0(section_id, "-REPEAT"), term = 202080L, final_grade = "B")
  i1 <- dplyr::filter(
    mc_outcomes(dplyr::bind_rows(test_students_mc, repeated_x), by_instructor = TRUE)$instructors,
    instructor == "MC_I1")
  expect_equal(c(i1$n_in_x, i1$n_took_y), c(4L, 3L))
  expect_equal(i1$pct_took_y, 75)
})

test_that("strictly prior and same-term passes are not conflated", {
  students <- dplyr::bind_rows(
    test_students_mc,
    .mc_row("MC_A3", 201980, "SPAN 201", "ABQ", "SPAN", grade = "A", instructor = "MC_I9"),
    .mc_row("MC_A4", 202010, "SPAN 201", "ABQ", "SPAN", grade = "A", instructor = "MC_I9")
  )
  r <- mc_outcomes(students, by_instructor = TRUE)
  i1 <- dplyr::filter(r$instructors, instructor == "MC_I1")
  expect_equal(c(i1$n_passed_y_before_x, i1$n_passed_y_same_term), c(1L, 1L))
  expect_equal(c(i1$n_eligible, i1$n_took_y), c(3L, 3L))
  expect_equal(i1$pct_took_y, 100)

  order_abq <- dplyr::filter(r$order_by_year, campus == "ABQ", acad_year == "2019-2020")
  expect_equal(order_abq$students_taking_x, 4L)
  expect_equal(c(order_abq$passed_y_before_x, order_abq$passed_y_same_term,
                 order_abq$passed_y_before_or_same), c(1L, 1L, 2L))
})

test_that("campus is filtered before the cohort, and every table is split by it", {
  all_campuses <- mc_outcomes()$summary
  expect_equal(all_campuses$campus, c("ABQ", "GA"))
  expect_equal(all_campuses$n_in_x, c(4L, 2L))
  # MC_G1 took SPAN 101 at GA and SPAN 201 at ABQ: a GA continuer.
  expect_equal(all_campuses$n_took_y, c(3L, 1L))

  abq <- mc_outcomes(campus = "ABQ")
  expect_equal(abq$summary$campus, "ABQ")
  expect_equal(abq$summary$n_took_y, 3L)
  expect_equal(sum(abq$order_by_year$students_taking_x), 4L)
})

test_that("a later course with no recorded grade is unknown, not a failure", {
  students <- test_students_mc %>%
    dplyr::mutate(final_grade = dplyr::if_else(
      student_id == "MC_A2" & subject_course == "SPAN 201", NA_character_, final_grade))
  s <- mc_outcomes(students)$summary
  expect_equal(sum(s$n_took_y), 4L)
  expect_equal(sum(s$n_graded), 3L)
  expect_equal(sum(s$n_no_outcome), 1L)
  expect_equal(sum(s$n_dfw), 1L)
})

# ── The instructor balance check ─────────────────────────────────────────────

test_that("instructor balance compares the two largest groups of continuers", {
  r <- ds_balance(min_n = 3L)
  # DS_I1 and DS_I2 each sent 4 eligible students on to STAT 245.
  expect_equal(c(r$reference_instructor, r$comparison_instructor), c("DS_I1", "DS_I2"))
  expect_equal(c(r$reference_campus, r$comparison_campus), c("ABQ", "ABQ"))
  expect_equal(c(r$n_treatment, r$n_control), c(4L, 4L))
  expect_false(is.null(r$balance$smd_table))
  # The students counted are the breakdown's continuers, no more.
  continuers <- ds_outcomes(by_instructor = TRUE)$instructors
  expect_equal(sum(r$instructor_counts$n),
               sum(continuers$n_took_y[continuers$instructor != "Instructor not recorded"]))
})

test_that("too few instructor groups gives no balance and its counts, never an error", {
  r <- ds_balance()
  expect_null(r$balance)
  expect_equal(c(r$min_n, r$n_comparable, r$n_groups), c(15L, 0L, 2L))
  expect_error(ds_balance(min_n = 3L, reference_instructor = "Nobody"), "fewer than 3 students")
})

# ── The page: payload, tables, trend and words ───────────────────────────────

test_that("the payload always carries the instructor breakdown and its scope", {
  r <- ds_later_course()
  expect_s3_class(r, "later_course")
  expect_equal(r$campus, "ABQ")
  expect_null(r$balance)
  expect_equal(nrow(r$instructors), 3L)
  expect_error(later_course_headline(ds_outcomes()), "build_later_course")

  with_balance <- suppressMessages(later_course_balance(
    r, test_students_ds, ds_attempts, test_programs_ds, NULL, test_student_terms_ds,
    list(data_edges = ds01_edges, balance_min_n = 3L)))
  expect_equal(with_balance$balance$reference_instructor, "DS_I1")
  expect_equal(with_balance$summary, r$summary)
})

test_that("the instructor table leaves out groups with nobody to count and adds the bands", {
  r <- ds_later_course(campus = NULL, min_n = 2L)
  tbl <- later_course_instructor_table(r)
  expect_equal(tbl$instructor, c("DS_I1", "DS_I2", "Instructor not recorded", "DS_I3"))
  expect_equal(tbl$campus, c("ABQ", "ABQ", "ABQ", "GA"))
  # DS_I1's A students: DS_A1 and DS_A2, both passed STAT 245.
  i1 <- tbl[tbl$instructor == "DS_I1", ]
  expect_equal(c(i1$graded_A, i1$pass_A), c(2, 100))
  expect_equal(c(i1$graded_B, i1$graded_C), c(1L, 0L))
  expect_true(is.na(i1$pass_C))
  expect_true(all(c("pass_A", "pass_B", "pass_C", "graded_A", "graded_B", "graded_C") %in% names(tbl)))
})

test_that("a per-term rate is judged against chance and scatter, one term type at a time", {
  trend <- later_course_trend(later_course_trend_payload)
  expect_equal(nrow(trend), 8L)
  of <- function(campus, type, measure) {
    trend[trend$campus == campus & trend$term_type == type & trend$measure == measure, ]
  }
  took <- of("ABQ", "fall", "took_y")
  # Fall 2023 has 4 students and no rate; Fall 2024 is all too recent.
  expect_equal(c(took$n_terms, took$first_term, took$last_term), c(5L, 201880L, 202280L))
  expect_equal(c(took$first_pct, took$last_pct, took$pooled_pct), c(40, 60, 50))
  expect_equal(took$slope, 5)
  # The terms sit on the line, so chance is the whole error.
  expect_equal(c(took$se_chance, took$se_scatter, took$slope_se), c(sqrt(250) / 10, 0, sqrt(250) / 10))
  expect_equal(took$direction, "rising")

  pass <- of("ABQ", "fall", "pass")
  expect_equal(pass$slope, (-2 * 75 - 100 * 33 / 45 + 100 * 41 / 55 + 2 * 75) / 10)
  expect_equal(pass$direction, "steady")
  expect_equal(of("GA", "fall", "took_y")$slope, -5)
  expect_equal(of("GA", "fall", "took_y")$direction, "falling")

  # A large course that dips and recovers: far outside binomial chance, and
  # still not a trend, because the terms scatter around the line.
  dip <- of("EA", "fall", "took_y")
  expect_equal(dip$slope, 2.4)
  expect_gt(dip$slope, 2 * dip$se_chance)
  expect_equal(dip$se_scatter, sqrt((184 - 24^2 / 10) / 3 / 10))
  expect_equal(dip$slope_se, dip$se_scatter)
  expect_equal(dip$direction, "steady")
  expect_equal(c(of("EA", "fall", "pass")$slope, of("EA", "fall", "pass")$se_scatter), c(0, 0))

  # Two Springs are not a trend, and never join the Falls.
  spring <- of("ABQ", "spring", "took_y")
  expect_equal(c(spring$n_terms, spring$direction), c("2", "too_few_terms"))
  expect_true(is.na(spring$slope))
  expect_equal(nrow(later_course_trend(later_course_trend_payload, "fall")), 6L)
  expect_error(later_course_trend(later_course_trend_payload, "winter"), "Unknown term type")
})

test_that("the per-term table keeps a term with no rate and filters by term type", {
  falls <- later_course_term_table(later_course_trend_payload, "fall")
  expect_equal(unique(falls$term_type), "fall")
  abq <- falls[falls$campus == "ABQ", ]
  expect_equal(abq$term_x, c(201880L, 201980L, 202080L, 202180L, 202280L, 202380L, 202480L))
  expect_true(all(is.na(abq$pct_took_y[abq$term_x >= 202380L])))
  expect_equal(later_course_term_types(later_course_trend_payload), c("fall", "spring"))
})

test_that("the course-order table lists the two kinds of pass, then their union", {
  expect_named(later_course_order_table(ds_later_course()), c(
    "campus", "acad_year", "students_taking_x", "passed_y_before_x",
    "passed_y_same_term", "passed_y_before_or_same", "pct_before_or_same"))
})

test_that("the chart draws one line per campus, measure and term type", {
  p <- plotly::plotly_build(plot_later_course_trend(later_course_trend_payload, "fall"))
  expect_equal(length(p$x$data), 6L)
  expect_setequal(vapply(p$x$data, function(tr) tr$name, character(1)),
                  c("Took STAT 245, ABQ", "Took STAT 245, EA", "Took STAT 245, GA",
                    "Passed it, ABQ", "Passed it, EA", "Passed it, GA"))
  # A term with no rate is not a point.
  abq_took <- Filter(function(tr) tr$name == "Took STAT 245, ABQ", p$x$data)[[1]]
  expect_equal(as.numeric(abq_took$y), c(0.40, 0.45, 0.50, 0.55, 0.60))

  # Several term types drawn: each has its own line, named for it, so no line
  # joins a Fall term to a Spring one.
  both <- plotly::plotly_build(plot_later_course_trend(later_course_trend_payload))
  expect_equal(length(both$x$data), 8L)
  abq_fall <- Filter(function(tr) tr$name == "Took STAT 245, ABQ, Fall", both$x$data)[[1]]
  abq_spring <- Filter(function(tr) tr$name == "Took STAT 245, ABQ, Spring", both$x$data)[[1]]
  expect_equal(as.character(abq_fall$x), c("Fa 18", "Fa 19", "Fa 20", "Fa 21", "Fa 22"))
  expect_equal(as.character(abq_spring$x), c("Sp 19", "Sp 20"))
  expect_equal(as.numeric(abq_spring$y), c(0.40, 0.44))

  # One campus: the campus is not repeated in every legend entry.
  one <- plotly::plotly_build(plot_later_course_trend(ds_later_course(min_n = 2L)))
  expect_setequal(vapply(one$x$data, function(tr) tr$name, character(1)),
                  c("Took STAT 245", "Passed it"))
  # No term with a rate: nothing to draw.
  expect_null(plot_later_course_trend(ds_later_course(), "spring"))
})

test_that("the trend is said in words", {
  testthat::local_edition(3)
  expect_snapshot(cat(later_course_trend_sentences(later_course_trend_payload), sep = "\n"))
  expect_equal(later_course_trend_sentences(ds_later_course(), "spring"), character(0))
})

test_that("the page's text preview", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_later_course(ds_later_course(min_n = 5L)), sep = "\n"))
})

test_that("a set of later courses is named as any of them, with its pass rule", {
  testthat::local_edition(3)
  set <- build_later_course(test_students_mc, .impact_attempts, list(
    course_x = "SPAN 101", course_y = c("SPAN 101L", "SPAN 201"), window_terms = 2L,
    min_n = 1L, data_edges = .impact_edges))
  for (h in later_course_headline(set)) {
    expect_equal(h$steps$n[h$steps$role == "total"] - sum(h$steps$n[h$steps$role == "removed"]),
                 h$steps$n[h$steps$role == "denominator"])
  }
  expect_snapshot(cat(format_later_course(set, instructors = TRUE), sep = "\n"))
})
