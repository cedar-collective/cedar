# downstream_glance() (R/features/downstream-glance.R): Course Dynamics >
# Downstream > At a Glance, five steps read off the payloads the other views
# already compute. Each step is checked against the payload it reads, on the
# fixture that payload's own tests use:
#
#   in_course     HIST 1110 on the designed data (get_course_outcome_rates)
#   coming_back   RP01, HIST 499 on ABQ: passed 6 anchors / 4 returned, failed 1 / 1
#   non_takers    HIST 101 against similar students: return 60% against 10%
#   next_courses  DS01, STAT 145 into STAT 245 on ABQ
#   prepared      MC02, SPAN 101 into SPAN 201 on ABQ: DFW 1 of 3 against 0 of 1

test_that("every step waits for its payload, and a course without admissions records says so", {
  rows <- downstream_glance("HIST 1110")
  expect_equal(vapply(rows, `[[`, "", "step"), names(DOWNSTREAM_GLANCE_STEPS))
  expect_true(all(vapply(rows, `[[`, "", "status") == "pending"))
  no_app <- downstream_glance("HIST 1110", similar_available = FALSE)
  expect_equal(no_app[[3]]$status, "none")
})

test_that("the course's own step reads its DFW rate on the campus with the most attempts", {
  rates <- get_course_outcome_rates(keyed_attempts(test_students),
                                    list(course = "HIST 1110", data_edges = data_objects$cedar_edges),
                                    group_cols = c("campus", "college", "term", "subject_course"), min_n = 1L)
  row <- downstream_glance("HIST 1110", dfw_by_term = rates)[[1]]
  expect_equal(row$status, "ready")
  by_campus <- rates %>% dplyr::count(campus, wt = n_attempts, sort = TRUE)
  expect_equal(row$scope, by_campus$campus[[1]])
  scoped <- rates[rates$campus == row$scope, ]
  # One campus's rate, never a blend of campuses.
  expect_equal(row$bars$share, sum(scoped$n_dfw) / sum(scoped$n_attempts))
  expect_match(row$sentence, sprintf("%.1f%%", 100 * sum(scoped$n_dfw) / sum(scoped$n_attempts)), fixed = TRUE)
})

test_that("coming back sets the passers' return beside the non-passers'", {
  persistence <- suppressMessages(get_course_persistence(
    test_students_rp, test_degrees_rp, opt = list(course = "HIST 499", campus = "ABQ", min_n = 1L),
    student_terms = test_student_terms_rp))
  row <- downstream_glance("HIST 499", persistence = persistence)[[2]]
  expect_equal(row$status, "ready")
  expect_equal(row$scope, "ABQ")
  expect_equal(row$bars$label, c("Passed", "Did not pass"))
  # The early drop is neither group.
  not_passed <- persistence[!persistence$outcome %in% c("pass", "early drop"), ]
  expect_equal(row$bars$share, c(4 / 6, sum(not_passed$n_returned) / sum(not_passed$n_students)))
})

test_that("against non-takers reads the return finding and its verdict", {
  similar <- build_course_similar_students(ss_student_terms2, ss_attempts2, ss_app,
                                           ss_opt(course = "HIST 101", min_term_n = 1L))
  row <- downstream_glance("HIST 101", similar = similar)[[3]]
  finding <- course_similar_students_findings(similar)
  finding <- finding[finding$outcome == "return", ]
  expect_equal(row$status, "ready")
  expect_equal(row$sentence, finding$sentence)
  expect_equal(row$bars$share, c(finding$taker, finding$similar) / 100)
  expect_equal(row$tone, "better")
})

test_that("next courses reads the headline of the campus with the most students who could have", {
  later <- ds_later_course()
  row <- downstream_glance("STAT 145", later = later)[[4]]
  heads <- later_course_headline(later)
  main <- heads[[which.max(vapply(heads, function(h) as.numeric(h$n_eligible), numeric(1)))]]
  expect_equal(row$status, "ready")
  expect_equal(row$scope, main$campus)
  expect_equal(row$bars$share[[1]], main$pct_took_y / 100)
})

test_that("prepared for it reads the two DFW rates and the balance verdict", {
  testthat::local_edition(3)
  sequence <- suppressMessages(get_course_sequence_effect(
    test_students_mc, .impact_attempts, test_programs_mc, NULL,
    opt = list(course_x = "SPAN 101", course_y = "SPAN 201", campus = "ABQ", min_n = 1L),
    student_terms = test_student_terms_mc, data_edges = .impact_edges))
  row <- downstream_glance("SPAN 101", sequence = sequence)[[5]]
  expect_equal(row$status, "ready")
  expect_equal(row$bars$share, c(1 / 3, 0))
  expect_equal(row$verdict, "+33.3 points DFW")
  expect_equal(row$tone, "worse")
  expect_snapshot(cat(row$sentence))
})

test_that("a gap between groups that were not alike is stated with its caveat and takes no colour", {
  # ss_app_act: HIST 101's takers average 5 ACT points under their matches;
  # ss_app_act_alike: the same score on both sides.
  build <- function(app) build_course_similar_students(ss_student_terms2, ss_attempts2, app,
                                                       ss_opt(course = "HIST 101", term = 202010L))
  expect_equal(downstream_glance("HIST 101", similar = build(ss_app_act_alike))[[3]]$tone, "better")
  unlike <- downstream_glance("HIST 101", similar = build(ss_app_act))[[3]]
  expect_true(is.na(unlike$tone))
  testthat::local_edition(3)
  expect_snapshot(cat(unlike$sentence))
})
