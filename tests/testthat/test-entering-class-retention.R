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

test_that("EC01: a first-time class is who the record calls new, with summer starters in the fall class", {
  ft <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                     list(term_type = "fall", student_level = "UG", min_n = 1L, entry = "first_time",
                                          data_edges = ec01$edges), ec01$programs)
  # Fall 2019 is a class now (EC-P): the record says who is new.
  expect_equal(ft$n_entering[ft$step == 1L], c(1L, 4L, 4L))
  expect_equal(attr(ft, "n_first_term"), 0L)
  # Fall 2020: A B C D. Spring 2021 A B C; Fall 2021 A B; then A alone.
  expect_equal(ft$n_here[ft$term == 202080L], c(3L, 2L, 1L, 1L))
  # Fall 2021: F1 F2 F3 and the summer starter EC-S; EC-N never enrolled.
  expect_equal(attr(ft, "n_summer_starts"), 1L)
  expect_equal(ft$n_here[ft$term == 202180L], c(2L, 1L, NA, NA))
  # Full-time in the entering term: EC-S (part-time that fall) is out.
  full <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                       list(term_type = "fall", student_level = "UG", min_n = 1L, entry = "first_time",
                                            time_status = "FT", data_edges = ec01$edges), ec01$programs)
  expect_equal(full$n_entering[full$term == 202180L][1], 3L)
  transfer <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                           list(term_type = "fall", min_n = 1L, entry = "transfer", data_edges = ec01$edges),
                                           ec01$programs)
  expect_equal(transfer$term[1], 202080L)
  expect_equal(transfer$n_here, c(0L, 1L, 0L, 0L))
  expect_error(get_entering_class_retention(ec01$student_terms, NULL, list(entry = "first_time", data_edges = ec01$edges)),
               "programs")
  expect_error(get_entering_class_retention(ec01$student_terms, NULL, list(entry = "new", data_edges = ec01$edges)),
               "opt\\$entry")
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
               c("2nd semester (spring)", "3rd semester (fall)", "4th semester (spring)", "5th semester (fall)"))
  expect_equal(retention_milestone_label(c(10L, 11L, 20L), 202080L),
               c("11th semester (fall)", "12th semester (fall)", "21st semester (fall)"))
  ms <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                     list(term_type = "fall", student_level = "UG", min_n = 1L, data_edges = ec01$edges))
  testthat::local_edition(3)
  first_time <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                             list(term_type = "fall", student_level = "UG", min_n = 1L, entry = "first_time",
                                                  data_edges = ec01$edges), ec01$programs)
  expect_snapshot(cat(retention_milestone_sentence(list(milestones = ms)),
                      retention_milestone_sentence(list(milestones = first_time)), sep = "\n"))
  expect_equal(retention_milestone_sentence(list(milestones = ms[0, ])), character(0))
  # The chart: one line per step, each stopping at its last settled class.
  fig <- plotly::plotly_build(plot_entering_class_milestones(list(milestones = ms)))
  expect_equal(vapply(fig$x$data, function(t) length(t$x), integer(1)), c(2L, 2L, 1L, 1L))
})

test_that("EC01: with a pace, still here splits into degree, each pace, slower and gone", {
  r <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                    list(student_level = "UG", data_edges = ec01$edges, min_n = 1L, n_terms = 3L,
                                         term_type = "fall", pace = DEGREE_PACE_TERM_CREDITS))
  at <- function(term, step) as.list(r[r$term == term & r$step == step, ])
  parts <- c("n_degree", "n_four_year", "n_six_year", "n_slower", "n_credits_unknown", "n_gone")
  expect_equal(unlist(at(202080L, 1L)[parts], use.names = FALSE), c(1, 2, 0, 1, 0, 2))
  # EC-E is back after a term away, behind; EC-C has gone.
  expect_equal(unlist(at(202080L, 2L)[parts], use.names = FALSE), c(1, 1, 0, 2, 0, 2))
  expect_equal(unlist(at(202080L, 3L)[parts], use.names = FALSE), c(1, 1, 0, 0, 0, 4))
  # 12 credits after one term is the six-year pace; 15 after two is neither.
  expect_equal(unlist(at(202180L, 1L)[parts], use.names = FALSE), c(0, 1, 1, 0, 0, 1))
  expect_equal(unlist(at(202180L, 2L)[parts], use.names = FALSE), c(0, 0, 0, 1, 0, 2))
  # The parts are the class, and degree plus enrolled is "still here".
  known <- r[!is.na(r$n_here), ]
  expect_equal(unname(rowSums(known[parts])), known$n_entering)
  expect_equal(known$n_entering - known$n_gone, known$n_here)
  # The enrolled students' credits before the term: A 15, B 9, C 15.
  expect_equal(unlist(at(202080L, 1L)[c("credits_q1", "credits_median", "credits_q3")], use.names = FALSE), c(12, 15, 15))
  # Past the settled edge nothing is counted.
  expect_true(all(is.na(unlist(at(202180L, 3L)[parts]))))
  # Without a pace the table is as it was.
  plain <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                        list(student_level = "UG", data_edges = ec01$edges, min_n = 1L, n_terms = 3L,
                                             term_type = "fall"))
  expect_equal(names(plain), c("term", "step", "target_term", "n_entering", "n_here", "here_pct"))
  expect_equal(as.data.frame(r[names(plain)]), as.data.frame(plain), check.attributes = FALSE)
  expect_error(get_entering_class_retention(ec01$student_terms, NULL,
                                            list(data_edges = ec01$edges, pace = c(slow = 10, fast = 15))),
               "fastest first")
})

test_that("EC01: a transfer class can be narrowed by the credits its students brought", {
  run <- function(range) get_entering_class_retention(
    ec01$student_terms, ec01$degrees,
    list(term_type = "fall", min_n = 1L, entry = "transfer", data_edges = ec01$edges, n_terms = 2L,
         arrival_credits = range, pace = DEGREE_PACE_TERM_CREDITS), ec01$programs)
  # EC-E brought 45 credits: in the 30-to-59 band, in neither other.
  mid <- run(c(30, 60))
  expect_equal(mid$n_entering, c(1L, 1L))
  # Away in Spring 2021; back in Fall 2021 with 15 credits after two terms: slower than 10 a term.
  expect_equal(c(mid$n_gone[1], mid$n_slower[2]), c(1, 1))
  expect_equal(nrow(run(c(0, 30))), 0L)
  expect_equal(nrow(run(c(60, Inf))), 0L)
  expect_error(run(c(60, 30)), "arrival_credits")
  expect_equal(nrow(attr(mid, "n_arrival_unknown")), 0L)
})

test_that("EC01: a transfer student with no record of credit brought is in no band (ISSUES I74)", {
  # EC-E's totals are not on record: that is not "brought none".
  programs <- ec01$programs %>%
    dplyr::mutate(overall_credits_attempted = dplyr::if_else(student_id == "EC-E", NA_real_, overall_credits_attempted))
  run <- function(range) get_entering_class_retention(
    ec01$student_terms, ec01$degrees,
    list(term_type = "fall", min_n = 1L, entry = "transfer", data_edges = ec01$edges, n_terms = 2L,
         arrival_credits = range, pace = DEGREE_PACE_TERM_CREDITS), programs)
  low <- run(c(0, 30))
  expect_equal(nrow(low), 0L)
  expect_equal(attr(low, "n_arrival_unknown"), tibble::tibble(term = 202080L, n = 1L, n_class = 1L))
  expect_equal(nrow(run(c(30, 60))), 0L)
  # The class's only transfer student is unrecorded: the class is withheld.
  expect_equal(attr(low, "arrival_withheld"), 202080L)
})

test_that("EC01: a class with unrecorded transfer students is not read by band", {
  # EC-B and EC-C arrive as transfers beside EC-E; EC-C has no record. One of
  # three unrecorded: the Fall 2020 class keeps its count and loses its rates.
  programs <- ec01$programs %>%
    dplyr::mutate(student_population = dplyr::if_else(student_id %in% c("EC-B", "EC-C") & term == 202080L,
                                                      "New Transfer from NM Inst", student_population),
                  overall_credits_attempted = dplyr::if_else(student_id == "EC-C", NA_real_, overall_credits_attempted))
  run <- function(opt) get_entering_class_retention(
    ec01$student_terms, ec01$degrees,
    c(list(term_type = "fall", min_n = 1L, entry = "transfer", data_edges = ec01$edges, n_terms = 2L,
           arrival_credits = c(0, 30), pace = DEGREE_PACE_TERM_CREDITS), opt), programs)
  held <- run(list())
  expect_equal(held$n_entering, c(1L, 1L))
  expect_true(all(is.na(held$n_here)) && all(is.na(held$n_gone)) && all(is.na(held$here_pct)))
  expect_equal(attr(held, "arrival_withheld"), 202080L)
  # Allowing the share reads EC-B, the one recorded student who brought none.
  read <- run(list(max_unknown_share = 0.5))
  expect_equal(read$n_here, c(1L, 1L))
  expect_equal(length(attr(read, "arrival_withheld")), 0L)
})

test_that("EC01: the first first-time class is read from its entering term; other first-term students are not", {
  run <- function(entry) get_entering_class_retention(
    ec01$student_terms, ec01$degrees,
    list(term_type = "fall", student_level = "UG", min_n = 1L, entry = entry, data_edges = ec01$edges, n_terms = 2L,
         pace = DEGREE_PACE_TERM_CREDITS), ec01$programs)
  ft <- run("first_time")
  # EC-P, first-time in Fall 2019 (the table's first term): away in Spring 2020,
  # back in Fall 2020 with 15 credits after two terms: slower than 10 a term, not unknown.
  p <- ft[ft$term == 201980L & ft$step == 2L, ]
  expect_equal(c(p$n_slower, p$n_credits_unknown, p$n_gone), c(1L, 0L, 0L))
  expect_equal(attr(ft, "n_label_trusted"), 1L)
  # Later classes hold no one in the first term: nothing is trusted there.
  expect_equal(sum(ft$n_credits_unknown[ft$term > 201980L], na.rm = TRUE), 0L)
  expect_equal(attr(run("all"), "n_label_trusted"), 0L)
})

test_that("EC01: past the degree edge an application to graduate counts from the next term", {
  # Degrees are posted through Spring 2021. EC-D (Fall 2020 only) has applied to
  # graduate in Summer 2021; EC-C (gone after Spring 2021) in Fall 2021 itself.
  degrees <- dplyr::bind_rows(
    ec01$degrees %>% dplyr::mutate(graduation_status = "Awarded"),
    tibble::tibble(student_id = c("EC-D", "EC-C"), term = c(202160L, 202180L), graduation_status = "Pending"))
  edges <- utils::modifyList(ec01$edges, list(last_degree = 202110L))
  run <- function(degrees, edges) get_entering_class_retention(
    ec01$student_terms, degrees,
    list(term_type = "fall", student_level = "UG", min_n = 1L, data_edges = edges, n_terms = 3L,
         pace = DEGREE_PACE_TERM_CREDITS), ec01$programs)
  base <- run(ec01$degrees, ec01$edges)
  r <- run(degrees, edges)
  f20 <- function(x) x[x$term == 202080L, ]
  # Spring 2021: unchanged. Fall 2021: EC-D now has a degree. Spring 2022: EC-C too.
  expect_equal(f20(r)$n_here - f20(base)$n_here, c(0L, 1L, 2L))
  expect_equal(f20(r)$n_degree - f20(base)$n_degree, c(0L, 1L, 2L))
  expect_equal(f20(r)$n_gone - f20(base)$n_gone, c(0L, -1L, -2L))
  # The same applications inside the degree edge are not degrees.
  expect_equal(f20(run(degrees, ec01$edges))$n_here, f20(base)$n_here)
  no_edge <- ec01$edges; no_edge$last_degree <- NULL
  expect_error(run(degrees, no_edge), "last_degree")
})
