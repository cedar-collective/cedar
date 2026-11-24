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

test_that("XC01: a last term is not final until the terms after it had time to show a return", {
  open <- function(window) graduation_open_terms(build_graduation_dashboard(
    xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
    c(xc01$opt, list(line = 90, return_window = window))))
  # Given no time to return, both last terms are final; given two more terms,
  # only Fall 2020's absences could be read, so Spring 2021 is still open.
  expect_equal(open(0L), integer(0))
  expect_equal(open(2L), 202110L)
  # The default four terms reach past the edge for every term: none was read, none is marked.
  expect_equal(open(4L), integer(0))
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

test_that("XC01: a credit line built over the scope's shared parts is the payload built alone", {
  opt <- function(line, ...) c(xc01$opt, list(line = line, min_list = 2L, ...))
  build <- function(line, parts = NULL, ...) build_graduation_dashboard(
    xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims, opt(line, ...),
    attempts = xc01$attempts, boards = xc01$boards, parts = parts)
  parts <- graduation_scope_parts(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, opt(90))
  # Who left and who passed the ceiling are counted once; every line reads them.
  for (line in GRADUATION_LINES) expect_identical(build(line, parts), build(line))
  # The payload is counted from the parts it is handed, not counted again:
  # with nobody in them, nobody was far along.
  nobody <- parts
  nobody$exit$students <- nobody$exit$students[0, ]
  expect_equal(build_graduation_dashboard(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, test_dims,
                                          opt(90), parts = nobody)$meta$n_far, 0L)
  # Parts counted under another scope are refused, never read as this one's.
  expect_error(build(90, parts, return_window = 0L), "another scope")
  elsewhere <- graduation_scope_parts(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                                      c(opt(90), list(campus = "EA")))
  expect_error(build(90, elsewhere), "another scope")
})

test_that("the Graduation page's scope has one form, and the page opens on a scope it can ask for", {
  scope <- graduation_page_scope("UG", c("EA", "ABQ"), "105")
  expect_identical(scope, list(level = "UG", campus = c("ABQ", "EA"), line = 105))
  # The same campuses in another order, or named twice, are the same scope.
  expect_identical(graduation_page_scope("UG", c("ABQ", "EA", "ABQ"), 105), scope)
  # No campus picked is every campus, however the browser says it.
  expect_null(graduation_page_scope("UG", character(0))$campus)
  expect_null(graduation_page_scope("UG", NULL)$campus)
  expect_error(graduation_page_scope(c("UG", "GR")), "one student level")
  expect_error(graduation_page_scope("UG", line = "most"), "one credit line")

  # It opens on the first level, the main campuses it offers and the first line.
  opens_on <- graduation_default_scope(c("ZZ", CEDAR_CAMPUS_MAIN))
  expect_identical(opens_on, list(level = names(CEDAR_STUDENT_LEVEL_LABELS)[[1]], campus = CEDAR_CAMPUS_MAIN,
                                  lines = GRADUATION_LINES))
  expect_identical(graduation_default_scope("ZZ")$campus, character(0))
  opt <- graduation_page_opt(graduation_page_scope(opens_on$level, opens_on$campus, opens_on$lines[[1]]),
                             xc01$opt$data_edges)
  expect_identical(opt, list(student_level = opens_on$level, campus = sort(CEDAR_CAMPUS_MAIN),
                             line = GRADUATION_LINES[[1]], data_edges = xc01$opt$data_edges, class_pace = FALSE))
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

test_that("EC01: a transfer class is described by what it earns here, not by a four-year pace", {
  pace <- get_entering_class_retention(ec01$student_terms, ec01$degrees,
                                       list(term_type = "fall", min_n = 1L, entry = "transfer", data_edges = ec01$edges,
                                            n_terms = 4L, arrival_credits = c(30, 60), pace = DEGREE_PACE_TERM_CREDITS),
                                       ec01$programs)
  attr(pace, "started") <- "transfer"
  attr(pace, "arrival_band") <- "30 to 59"
  expect_equal(graduation_pace_shares(pace, 2L)$slower_pct, 100)
  expect_snapshot(cat(format_graduation_pace(pace), sep = "\n"))
})
