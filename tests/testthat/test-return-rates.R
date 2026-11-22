# RR01 (fixtures/scenario_tables.R): four falls of ABQ freshmen, EA
# sophomores, graduating seniors and graduate students, and a Fall 2024 whose
# return is not yet observable. rr01$dashboard is the page's payload over it
# (minimum 5 a rate; courses with 10 takers and 5 DFW).

test_that("RR01: a degree that term and an unsettled next term stay out of the rate, counted", {
  r <- get_return_rates(rr01$student_terms, list(term_type = "fall", student_level = "UG", data_edges = rr01_edges))$rates
  expect_equal(r$term, c(202080L, 202180L, 202280L, 202380L, 202480L))
  expect_equal(r$n_enrolled, c(62L, 62L, 62L, 62L, 10L))
  expect_equal(r$n_graduated, c(2L, 2L, 2L, 2L, 0L))
  expect_equal(r$n_unobservable, c(0L, 0L, 0L, 0L, 10L))
  expect_equal(r$n_observable, c(60L, 60L, 60L, 60L, 0L))
  expect_equal(r$n_returned, c(43L, 45L, 47L, 49L, 0L))
  expect_equal(r$return_pct, c(100 * c(43, 45, 47, 49) / 60, NA))
})

test_that("RR01: the level scope keeps graduate students out, and every level reads them", {
  all_levels <- get_return_rates(rr01$student_terms, list(term_type = "fall", data_edges = rr01_edges))$rates
  expect_equal(all_levels$n_observable[1:4], rep(65L, 4))
  expect_equal(all_levels$n_returned[1:4], c(48L, 50L, 52L, 54L))
})

test_that("RR01: each home campus is its own row, and a small one gets no rate", {
  r <- get_return_rates(rr01$student_terms, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "student_campus", min_n = 25L)))$rates
  fall20 <- r[r$term == 202080L, ]
  expect_equal(fall20$student_campus, c("ABQ", "EA"))
  expect_equal(fall20$n_observable, c(40L, 20L))
  expect_equal(fall20$n_returned, c(28L, 15L))
  expect_equal(fall20$return_pct, c(70, NA))
})

test_that("RR01: the DFW sign is unknown without a posted grade and past the graded edge", {
  r <- get_return_rates(rr01$student_terms, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "dfw")))$rates
  fall22 <- r[r$term == 202280L, ]
  expect_equal(fall22$dfw, c(FALSE, TRUE, NA))
  expect_equal(fall22$n_observable, c(52L, 7L, 1L))
  expect_equal(fall22$n_returned, c(45L, 2L, 0L))
  # Fall 2023 is past the graded edge (Fall 2022): every student-term unknown.
  fall23 <- r[r$term == 202380L, ]
  expect_equal(nrow(fall23), 1L)
  expect_true(is.na(fall23$dfw))
  expect_equal(fall23$n_observable, 60L)
})

test_that("RR01: a late withdrawal is any course dropped after census", {
  r <- get_return_rates(rr01$student_terms, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "late_withdrawal")))$rates
  fall23 <- r[r$term == 202380L, ]
  expect_equal(fall23$late_withdrawal, c(FALSE, TRUE))
  expect_equal(fall23$n_observable, c(54L, 6L))
  expect_equal(fall23$n_returned, c(49L, 0L))
})

test_that("get_return_rates() stops on an unknown group, a missing edge or a missing column", {
  st <- rr01$student_terms
  expect_error(get_return_rates(st, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "major"))), "group_cols")
  expect_error(get_return_rates(st, list(term_type = "fall")), "settled enrollment edge")
  expect_error(get_return_rates(st, list(group_cols = "dfw",
                                         data_edges = list(last_enrolled_complete = 202480L))), "last_graded")
  expect_error(get_return_rates(dplyr::select(st, -degree_awarded), list(term_type = "fall", student_level = "UG", data_edges = rr01_edges)), "degree_awarded")
})

test_that("RR01: the dashboard's signs compare with and without, and share the non-returners", {
  p <- rr01$dashboard
  expect_equal(p$series$term, c(202080L, 202180L, 202280L, 202380L))
  latest <- p$signs_latest
  lw <- latest[latest$sign == "late_withdrawal", ]
  expect_equal(lw$term, 202380L)
  expect_equal(c(lw$n_with, lw$returned_with, lw$n_without, lw$returned_without), c(6L, 0L, 54L, 49L))
  expect_equal(lw$share_of_nonreturners_pct, 100 * 6 / 11)
  # The DFW sign's latest known term is the graded edge's, Fall 2022.
  dfw <- latest[latest$sign == "dfw", ]
  expect_equal(dfw$term, 202280L)
  expect_equal(c(dfw$n_with, dfw$returned_with, dfw$n_without, dfw$returned_without), c(7L, 2L, 52L, 45L))
  expect_equal(dfw$share_of_nonreturners_pct, 100 * 5 / 12)
})

test_that("RR01: each classification and college is its own series", {
  g <- rr01$dashboard$groups
  expect_setequal(paste(g$dimension, g$group),
                  c("classification Freshman, 1st Yr, 1st Sem", "classification Sophomore, 2nd Yr",
                    "college AS", "college EN"))
  fresh <- g[g$group == "Freshman, 1st Yr, 1st Sem", ]
  expect_equal(fresh$rates[[1]], 100 * c(28, 30, 32, 34) / 40)
  expect_equal(fresh$n_terms, 4L)
})

test_that("RR01: a classification not read in the latest term is left out, counted", {
  p <- rr01$dashboard
  expect_false("Junior, 3rd Yr" %in% p$groups$group)
  expect_equal(p$meta$n_groups_past, 1L)
})

test_that("RR01: a scope with no student to read is an empty payload, not an error", {
  p <- build_retention_dashboard(rr01$student_terms, rr01$attempts, NULL, list(
    term_type = "fall", student_level = "UG", campus = "LA", data_edges = rr01_edges, min_n = 5L))
  expect_equal(nrow(p$series), 0L)
  expect_null(p$groups)
  expect_null(p$courses$listed)
  expect_match(format_retention_dashboard(p)[[3]], "no student in this scope")
})

test_that("RR01: the courses read the latest graded falls' students", {
  courses <- rr01$dashboard$courses
  expect_equal(courses$terms, c(202080L, 202180L, 202280L))
  expect_equal(courses$listed$subject_course, "MATH 101")
  expect_equal(courses$listed$campus, "ABQ")
  expect_equal(c(courses$listed$pop_n_dfw, courses$listed$pop_n_pass), c(21L, 96L))
  expect_equal(courses$listed$pop_dfw_stopout_rate, 19 / 21)
  # 21 DFW students, 19 not back, against the passers' 8 of 96 not back.
  expect_equal(courses$listed$excess_not_back, 21 * (19 / 21 - 8 / 96))
})

test_that("RR01: the trend carries its fitted line's ends, the least-squares line through the terms", {
  # plot_return_series() draws the trend from these, so the dashed line is the
  # fit the verdict was read from.
  s <- rr01$dashboard$series
  t <- rr01$dashboard$trend
  fit <- stats::lm(return_pct ~ I(term %/% 100L), data = s)
  expect_equal(t$fit_first_pct, unname(stats::fitted(fit)[1]))
  expect_equal(t$fit_last_pct, unname(stats::fitted(fit)[nrow(s)]))
  expect_equal((t$fit_last_pct - t$fit_first_pct) / ((t$last_term - t$first_term) %/% 100L), t$slope)
})

# RR01's students each hold one term's row (a new id every fall), so every
# entering class reads 0% still enrolled: the text shows the lines are there.
# The arithmetic is EC01's (test-entering-class-retention.R).
test_that("RR01: the dashboard as text", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_retention_dashboard(rr01$dashboard), sep = "\n"))
})

test_that("RR01: the first section's sentence gives the verdict over the terms, and says when too few can be read", {
  testthat::local_edition(3)
  t <- rr01$dashboard$trend[1, , drop = FALSE]
  few <- t
  few$direction <- "too_few_terms"
  few$n_terms <- 2L
  expect_snapshot(cat(retention_lead_sentence(t, "fall"), retention_trend_arithmetic(t),
                      retention_lead_sentence(few, "fall"), sep = "\n"))
})

test_that("SG01: a spring student awarded a degree that summer finished, and is not a student who left", {
  r <- get_return_rates(sg01$student_terms, sg01$opt, sg01$degrees)$rates
  s22 <- r[r$term == 202210L, ]
  expect_equal(c(s22$n_enrolled, s22$n_graduated, s22$n_finished_between, s22$n_applied_between,
                 s22$n_observable, s22$n_returned), c(7L, 4L, 3L, 0L, 3L, 1L))
  # Summer 2023's degrees are not posted: the application stands in, counted apart.
  s23 <- r[r$term == 202310L, ]
  expect_equal(c(s23$n_graduated, s23$n_finished_between, s23$n_applied_between, s23$n_observable, s23$n_returned),
               c(1L, 0L, 1L, 1L, 1L))
  # Without the degrees table only the term's own degree is completion.
  plain <- get_return_rates(sg01$student_terms, sg01$opt)
  expect_equal(c(plain$rates$n_graduated[1], plain$rates$n_observable[1]), c(1L, 6L))
  expect_false(plain$meta$between_terms)
  # A fall's next regular term is the spring: nothing lies between.
  fall <- get_return_rates(sg01$student_terms, utils::modifyList(sg01$opt, list(term_type = "fall")), sg01$degrees)$rates
  expect_equal(sum(fall$n_finished_between + fall$n_applied_between), 0L)
  no_degree_edge <- sg01$opt
  no_degree_edge$data_edges <- list(last_enrolled_complete = 202380L)
  expect_error(get_return_rates(sg01$student_terms, no_degree_edge, sg01$degrees), "degree edge")
})
