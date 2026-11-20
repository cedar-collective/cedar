# EC01 (fixtures/scenario_tables.R): a Fall 2020 class of six and a Fall 2021
# class of three, followed to Fall 2022, with the counts written above the
# fixture.

test_that("EC01: each entering class is followed step by step, and a degree is still here", {
  r <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                    list(term_type = "fall", student_level = "UG", min_n = 1L, data_edges = ec01$edges))
  f20 <- r[r$term == 202080L, ]
  expect_equal(f20$step, 1:4)
  expect_equal(f20$target_term, c(202110L, 202180L, 202210L, 202280L))
  expect_equal(f20$n_entering, rep(6L, 4))
  expect_equal(f20$n_here, c(4L, 4L, 2L, 2L))
  expect_equal(f20$here_pct, 100 * c(4, 4, 2, 2) / 6)
  # Fall 2021: two steps settled, the rest unknown, never zero.
  f21 <- r[r$term == 202180L, ]
  expect_equal(f21$n_entering, rep(3L, 4))
  expect_equal(f21$n_here, c(2L, 1L, NA, NA))
  expect_true(all(is.na(f21$here_pct[3:4])))
  # The table's first term is nobody's entering class: EC-P is left out, counted.
  expect_false(201980L %in% r$term)
  expect_equal(attr(r, "first_term"), 201980L)
  expect_equal(attr(r, "n_first_term"), 1L)
  expect_equal(attr(r, "edge"), 202280L)
})

test_that("EC01: without the degrees a graduate reads as gone, and the scope narrows the class", {
  no_deg <- get_entering_class_retention(ec01$student_terms, NULL,
                                         list(term_type = "fall", student_level = "UG", min_n = 1L, data_edges = ec01$edges))
  expect_equal(no_deg$n_here[no_deg$term == 202080L], c(4L, 3L, 1L, 1L))
  # Every level: the graduate student joins the Fall 2021 class.
  every <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                        list(term_type = "fall", min_n = 1L, data_edges = ec01$edges))
  expect_equal(every$n_entering[every$term == 202180L][1], 4L)
  # One entering classification: EC-E (a sophomore at entry) is out.
  fresh <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                        list(term_type = "fall", student_level = "UG", min_n = 1L,
                                             classification = "Freshman, 1st Yr, 1st Sem", data_edges = ec01$edges))
  expect_equal(fresh$n_entering[fresh$term == 202080L][1], 5L)
  expect_equal(fresh$n_here[fresh$term == 202080L], c(4L, 3L, 2L, 2L))
  # A class under the guard keeps its counts and has no rate.
  guarded <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                          list(term_type = "fall", student_level = "UG", min_n = 5L, data_edges = ec01$edges))
  expect_equal(guarded$n_here[guarded$term == 202180L][1], 2L)
  expect_true(is.na(guarded$here_pct[guarded$term == 202180L][1]))
  expect_false(is.na(guarded$here_pct[guarded$term == 202080L][1]))
  # No spring class in the fixture: an empty table, not an error.
  expect_equal(nrow(get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                                 list(term_type = "spring", data_edges = ec01$edges))), 0L)
})

test_that("get_entering_class_retention() stops without its edge, its columns or a step", {
  expect_error(get_entering_class_retention(ec01$student_terms, NULL, list()), "settled enrollment edge")
  expect_error(get_entering_class_retention(ec01$student_terms %>% select(-student_level), NULL,
                                            list(data_edges = ec01$edges)), "student_level")
  expect_error(get_entering_class_retention(ec01$student_terms, NULL, list(data_edges = ec01$edges, n_terms = 0L)),
               "at least 1")
})

test_that("EC01: a step is named by its distance and season, and the sentence reads the latest class a year on", {
  expect_equal(retention_milestone_label(1:4, c(202110L, 202180L, 202210L, 202280L)),
               c("1 semester later (spring)", "1 year later (fall)", "3 semesters later (spring)", "2 years later (fall)"))
  ms <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                     list(term_type = "fall", student_level = "UG", min_n = 1L, data_edges = ec01$edges))
  testthat::local_edition(3)
  expect_snapshot(cat(retention_milestone_sentence(list(milestones = ms))))
  expect_equal(retention_milestone_sentence(list(milestones = ms[0, ])), character(0))
  # The chart: one line per step, each stopping at its last settled class.
  fig <- plotly::plotly_build(plot_entering_class_milestones(list(milestones = ms)))
  expect_equal(vapply(fig$x$data, function(t) length(t$x), integer(1)), c(2L, 2L, 1L, 1L))
})
