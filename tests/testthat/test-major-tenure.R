# MT01 (fixtures/scenario_tables.R): entrants to a major, semester by semester.

testthat::local_edition(3)

test_that("MT01: where a major's entrants are at each semester after entering", {
  r <- get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, mt01$opt)
  # Five entered where it can be seen; M-E was in it when the data begin.
  expect_equal(c(r$meta$n_entered, r$meta$n_unclear), c(5L, 1L))
  expect_equal(c(r$meta$first_entry, r$meta$last_entry), c(202080L, 202180L))
  # M-D's third and fourth semesters are past the settled edge: four followed.
  expect_equal(r$steps$n_observed, c(5L, 5L, 4L, 4L))
  expect_equal(r$steps$n_in_major, c(5L, 2L, 1L, 0L))
  expect_equal(r$steps$n_other_major, c(0L, 1L, 1L, 1L))
  expect_equal(r$steps$n_no_major, c(0L, 1L, 0L, 0L))
  # M-C's degree counts from the term it was awarded, whatever they enrolled in.
  expect_equal(r$steps$n_degree, c(0L, 0L, 1L, 1L))
  expect_equal(r$steps$n_not_enrolled, c(0L, 1L, 1L, 2L))
  expect_equal(rowSums(r$steps[names(MAJOR_TENURE_STATES)]), r$steps$n_observed, ignore_attr = TRUE)

  # Degrees posted only through Spring 2021: M-D's entering term cannot be
  # read, so M-D is not an entrant, and no step past Spring 2021 is read.
  early <- mt01$opt
  early$data_edges$last_degree <- 202110L
  e <- get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, early)
  expect_equal(e$meta$n_entered, 4L)
  expect_equal(e$steps$n_observed, c(4L, 4L, 0L, 0L))

  expect_error(get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, list(data_edges = mt01$opt$data_edges)),
               "program_codes")
  expect_error(get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, list(program_codes = "UNDC")),
               "settled and degree edges")
  expect_error(get_major_tenure(dplyr::select(mt01$population, -first_unit_term), mt01$student_terms, mt01$degrees, mt01$opt),
               "lacks first_unit_term")
})

test_that("MT01: entrants by how they arrived", {
  all <- get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, mt01$opt, programs = mt01$programs)
  # The whole population is unchanged by the labels, and every entrant is in one group.
  expect_equal(all$steps, get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, mt01$opt)$steps)
  expect_equal(all$meta$by_arrival$n, c(2L, 1L, 2L))
  expect_equal(sum(all$meta$by_arrival$n), all$meta$n_entered)

  first <- get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees,
                            c(mt01$opt, list(arrival = "first_time")), programs = mt01$programs)
  # M-A and M-D; M-D can be followed two steps.
  expect_equal(first$steps$n_observed, c(2L, 2L, 1L, 1L))
  expect_equal(first$steps$n_in_major, c(2L, 2L, 0L, 0L))
  expect_equal(first$steps$n_other_major, c(0L, 0L, 1L, 1L))
  here <- get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees,
                           c(mt01$opt, list(arrival = "already_here")), programs = mt01$programs)
  # M-C and M-F: neither is new that term.
  expect_equal(here$steps$n_observed, c(2L, 2L, 2L, 2L))
  expect_equal(here$steps$n_degree, c(0L, 0L, 1L, 1L))

  expect_error(get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, c(mt01$opt, list(arrival = "transfer"))),
               "needs programs")
  expect_error(get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, c(mt01$opt, list(arrival = "other"))),
               "must be one of")
  expect_snapshot(cat(major_tenure_lead(first, "Undecided", min_n = 1L)))
})

test_that("MT01: the page's view of it", {
  r <- get_major_tenure(mt01$population, mt01$student_terms, mt01$degrees, mt01$opt)
  s <- major_tenure_shares(r, min_n = 5L)
  # Under the floor a semester is not drawn.
  expect_equal(s$step, c(0L, 1L))
  expect_equal(s$in_major_pct, c(100, 40))
  drawn <- plotly::plotly_build(plot_major_tenure(r, min_n = 1L))$x$data
  expect_equal(vapply(drawn, function(t) t$name, character(1)), unname(MAJOR_TENURE_STATES))
  expect_snapshot(cat(format_major_tenure(r, "Undecided"), sep = "\n"))
})
