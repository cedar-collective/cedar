# XC01 (fixtures/scenario_tables.R) through the Graduation payload. The cone's
# counts are tested in test-exit-credits.R; here, what the page adds: the
# far-along students, their terms, colleges and majors, and the page's words.

testthat::local_edition(3)

test_that("XC01: the far-along students are counted by term, college and major", {
  p <- build_graduation_dashboard(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
                                  c(xc01$opt, list(line = 90, min_list = 2L)))
  # At 90 or more: X-A (100), X-B (120), X-J (118), X-K (125); two at 120 or more.
  expect_equal(c(p$meta$n_far, p$meta$n_done, p$meta$n_not_recorded), c(4L, 2L, 1L))
  expect_equal(p$series$exit_term, c(202080L, 202110L))
  expect_equal(p$series$n_left, c(1L, 6L))
  expect_equal(p$series$n_far, c(0L, 4L))
  expect_equal(p$series$n_done, c(0L, 2L))
  expect_equal(c(p$colleges$group, p$colleges$n), c("AS", "4"))
  expect_setequal(p$majors$group, c("ANTH", "HIST"))
  expect_equal(p$majors$n, c(2L, 2L))
  expect_equal(p$majors$n_done[p$majors$group == "HIST"], 2L)
  expect_equal(p$majors$n_flagged[p$majors$group == "HIST"], 1L)
  expect_equal(p$meta$n_majors_pooled, 0L)

  # A higher line narrows the group; a major under the listing floor is pooled.
  top <- build_graduation_dashboard(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
                                    c(xc01$opt, list(line = 120)))
  expect_equal(top$meta$n_far, 2L)
  expect_equal(nrow(top$majors), 1L)
  expect_equal(c(top$majors$n, top$meta$n_majors_pooled), c(2L, 1L))
  expect_true(is.na(top$majors$group))
  expect_error(build_graduation_dashboard(dplyr::select(xc01$student_terms, -primary_college_code), xc01$programs,
                                          xc01$degrees, xc01$terms, test_dims, xc01$opt),
               "lacks primary_college_code")
  expect_error(build_graduation_dashboard(dplyr::select(xc01$student_terms, -is_pre_major), xc01$programs,
                                          xc01$degrees, xc01$terms, test_dims, xc01$opt),
               "lacks is_pre_major")
})

test_that("XC01: with attempts and boards the payload counts each plan's required courses", {
  p <- build_graduation_dashboard(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
                                  c(xc01$opt, list(line = 90, min_list = 2L)), attempts = xc01$attempts,
                                  boards = xc01$boards)
  t <- graduation_required_table(p)
  expect_equal(t$plan, c("Anthropology B.A.", rep("History B.A.", 4)))
  expect_equal(t$n_tried, c(1L, 0L, 0L, 1L, NA))
  expect_equal(p$required$programs$n_not_read, c(0L, 2L))
  # X-A earned 40 of 100 here; the other three all of theirs.
  expect_equal(c(p$meta$n_far_here_known, p$meta$n_far_mostly_elsewhere), c(4L, 1L))
  expect_equal(c(p$meta$median_credits, p$meta$median_credits_here), c(119, 119))
  expect_snapshot(cat(format_graduation_dashboard(p)[-(1:25)], sep = "\n"))
})

test_that("XC01: the page's words", {
  p <- build_graduation_dashboard(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
                                  c(xc01$opt, list(line = 90, min_list = 2L)))
  none <- build_graduation_dashboard(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
                                     c(xc01$opt, list(first_exit_term = 202310L)))
  expect_snapshot({
    cat(format_graduation_dashboard(p), sep = "\n")
    cat("\n", graduation_headline(none), "\n")
  })
  expect_equal(graduation_band_table(p)$n, c(1L, 0L, 1L, 1L, 1L, 2L, 1L))
})

test_that("EC01: the entering classes' pace, as the page shows it", {
  pace <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                       list(student_level = "UG", data_edges = ec01$edges, min_n = 1L, n_terms = 4L,
                                            term_type = "fall", pace = DEGREE_PACE_TERM_CREDITS))
  s <- graduation_pace_shares(pace, 2L)
  # Fall 2020: one degree, one on the four-year pace, two slower, two gone of six.
  expect_equal(s$class, c("Fall 2020", "Fall 2021"))
  expect_equal(unlist(s[1, c("degree_pct", "four_year_pct", "slower_pct", "gone_pct")], use.names = FALSE),
               100 * c(1, 1, 2, 2) / 6)
  # The shares are the whole class.
  expect_equal(rowSums(s[grepl("_pct$", names(s)) & names(s) != "here_pct"]), c(100, 100))
  # Fall 2021's fourth term is past the settled edge: one class left.
  expect_equal(graduation_pace_shares(pace, 4L)$class, "Fall 2020")
  expect_snapshot(cat(format_graduation_pace(pace), sep = "\n"))
})
