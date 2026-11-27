# Bird's Eye > DFW: the lower-division DFW dashboard's cones and payload, on
# fixture DF01 (designed_test_data.R; edges in helper-scenario-edges.R).

test_that("the UNM-wide series counts lower-division fall attempts to the graded edge", {
  s <- get_dfw_term_series(df_attempts, df01_fall_opt)
  expect_equal(s$terms$term, c(201980L, 202080L, 202180L, 202280L))
  # 140 a fall: the upper-division course, the spring term, the term past the
  # edge and the early drop are none of them counted.
  expect_equal(s$terms$n_attempts, rep(140L, 4))
  expect_equal(s$terms$n_dfw, c(32L, 44L, 32L, 45L))
  expect_equal(s$terms$dfw_pct, 100 * c(32, 44, 32, 45) / 140)
  fall_2022 <- s$terms[s$terms$term == 202280L, ]
  expect_equal(c(fall_2022$n_w, fall_2022$n_f, fall_2022$n_d + fall_2022$n_c_minus,
                 fall_2022$n_other_nonpassing, fall_2022$n_nr),
               c(13L, 19L, 12L, 1L, 1L))
  expect_equal(fall_2022$n_w + fall_2022$n_f + fall_2022$n_d + fall_2022$n_c_minus + fall_2022$n_other_nonpassing,
               fall_2022$n_dfw)
  expect_equal(s$trend$direction, "steady")
  expect_equal(s$meta$graded_edge, 202280L)
})

test_that("the series reads campus and college apart", {
  by_campus <- get_dfw_term_series(df_attempts, df01_fall_opt, "campus")
  ea <- by_campus$terms[by_campus$terms$campus == "EA", ]
  expect_equal(ea$n_dfw, rep(10L, 4))
  expect_equal(ea$n_attempts, rep(30L, 4))
  expect_equal(by_campus$trend$direction[by_campus$trend$campus == "EA"], "steady")
  by_college <- get_dfw_term_series(df_attempts, df01_fall_opt, "college")
  expect_setequal(by_college$trend$college, c("AS", "UC"))
  expect_equal(by_college$trend$direction[by_college$trend$college == "UC"], "falling")
})

test_that("the series refuses a mixed or missing term type, another grouping and another edge", {
  expect_error(get_dfw_term_series(df_attempts, list(data_edges = df01_edges)), "term_type")
  expect_error(get_dfw_term_series(df_attempts, list(term_type = c("fall", "spring"))), "term_type")
  expect_error(get_dfw_term_series(df_attempts, df01_fall_opt, "subject_course"), "group_cols")
  expect_error(get_dfw_term_series(df_attempts, modifyList(df01_fall_opt, list(data_edges = list(last_graded = 202180L)))),
               "graded edge|built to")
})

test_that("the DFW scope reads only the terms and campuses chosen", {
  middle <- get_dfw_term_series(df_attempts, modifyList(df01_fall_opt, list(from_term = 202080L, to_term = 202180L)))
  expect_equal(middle$terms$term, c(202080L, 202180L))
  expect_equal(middle$terms$n_dfw, c(44L, 32L))
  # The early terms and the last one are left out of the line too: two terms
  # are too few for a trend.
  expect_equal(middle$trend$direction, "too_few_terms")
  from_2020 <- prepare_dfw_attempts(df_attempts, modifyList(df01_fall_opt, list(from_term = 202080L)))
  expect_equal(sort(unique(from_2020$term)), c(202080L, 202180L, 202280L))

  ea <- get_dfw_term_series(df_attempts, modifyList(df01_fall_opt, list(campus = "EA")))
  expect_equal(ea$terms$n_attempts, rep(30L, 4))
  both <- get_dfw_term_series(df_attempts, modifyList(df01_fall_opt, list(campus = c("ABQ", "EA"))))
  every <- get_dfw_term_series(df_attempts, df01_fall_opt)
  abq_ea <- df_attempts %>% dplyr::filter(campus %in% c("ABQ", "EA"))
  expect_lte(sum(both$terms$n_attempts), sum(every$terms$n_attempts))
  expect_equal(sum(both$terms$n_attempts),
               nrow(prepare_dfw_attempts(abq_ea, df01_fall_opt)))

  expect_error(prepare_dfw_attempts(df_attempts, modifyList(df01_fall_opt, list(from_term = 202280L, to_term = 202080L))),
               "after opt\\$max_term")
})

test_that("the dashboard's campus table reads every campus whichever the page scopes to", {
  p <- build_dfw_dashboard(df_attempts, test_dims, modifyList(df01_fall_opt, list(campus = "EA")))
  every <- get_dfw_term_series(df_attempts, df01_fall_opt, "campus")
  expect_setequal(p$by_campus$trend$campus, every$trend$campus)
  expect_true(length(unique(every$trend$campus)) > 1L)
  # The rest of the page is EA's.
  expect_equal(unique(p$courses$courses$campus), "EA")
  expect_setequal(unique(p$by_college$terms$college),
                  unique(dplyr::filter(df_attempts, campus == "EA", level == "lower")$college))
  expect_equal(p$meta$campus, "EA")
})

test_that("a rate trend refuses two terms of one year in a line", {
  two_types <- df_attempts %>%
    dplyr::filter(subject_course == "MATH 1220", campus == "ABQ") %>%
    dplyr::count(term, name = "n") %>%
    dplyr::mutate(k = 1L)
  expect_error(compute_rate_trend(two_types, min_terms = 3L), "two terms of one year")
})

test_that("the course board ranks campus-courses by DFW grades in the window", {
  b <- get_dfw_course_board(df_attempts, df01_fall_opt)
  expect_equal(b$meta$window_terms, c(202080L, 202180L, 202280L))
  expect_equal(paste(b$courses$subject_course, b$courses$campus),
               c("MATH 1220 ABQ", "PSYC 1110 ABQ", "MATH 1220 EA", "ENGL 1110 ABQ"))
  expect_equal(b$courses$n_dfw, c(37L, 36L, 30L, 18L))
  expect_equal(b$courses$n_attempts, c(90L, 120L, 90L, 120L))
  expect_equal(b$courses$cum_share, cumsum(c(37, 36, 30, 18)) / 121)
  expect_equal(b$totals[c("n_courses", "n_attempts", "n_dfw", "courses_for_quarter", "courses_for_half")],
               list(n_courses = 4L, n_attempts = 420L, n_dfw = 121L, courses_for_quarter = 1L, courses_for_half = 2L))
  expect_equal(b$courses$college, c("AS", "AS", "AS", "UC"))
})

test_that("the course board's trends say which course rises, falls, holds and swings", {
  b <- get_dfw_course_board(df_attempts, df01_fall_opt)
  by_course <- stats::setNames(b$courses$direction, paste(b$courses$subject_course, b$courses$campus))
  expect_equal(unname(by_course[c("MATH 1220 ABQ", "ENGL 1110 ABQ", "MATH 1220 EA", "PSYC 1110 ABQ")]),
               c("rising", "falling", "steady", "steady"))
  expect_equal(b$courses$slope[b$courses$subject_course == "ENGL 1110"], -7.5)
  psyc <- b$courses[b$courses$subject_course == "PSYC 1110", ]
  # 10, 40, 10, 40%: a flat line 15 points from every term.
  expect_equal(psyc$resid_sd, sqrt(720 / 2))
  expect_lt(psyc$resid_p, 0.01)
  # All four have the four terms a scatter needs; the bar is shared.
  expect_equal(b$meta$n_swing_tests, 4L)
  expect_equal(b$meta$swing_p_cut, DFW_SWING_FAMILY_P / 4)
  expect_lt(psyc$swing_p, b$meta$swing_p_cut)
  expect_equal(b$courses$swings, c(FALSE, TRUE, FALSE, FALSE))
  # The typical course here holds to its line: half of the four have no
  # scatter beyond chance, so PSYC 1110 is judged against chance alone.
  expect_equal(b$meta$typical_extra_sd, 0)
})

test_that("a course that swings as much as most courses do is not called a swinger", {
  # The change: PSYC 1110's terms copied onto two more campuses, so three of
  # the six campus-courses swing 15 points a term and the typical course's
  # scatter beyond chance is PSYC's own.
  swinging <- dplyr::bind_rows(
    df_attempts,
    dplyr::mutate(dplyr::filter(df_attempts, subject_course == "PSYC 1110"), campus = "GA"),
    dplyr::mutate(dplyr::filter(df_attempts, subject_course == "PSYC 1110"), campus = "VA")
  )
  for (a in setdiff(names(attributes(df_attempts)), c("names", "row.names", "class"))) {
    attr(swinging, a) <- attr(df_attempts, a)
  }
  b <- get_dfw_course_board(swinging, df01_fall_opt)
  psyc <- b$courses[b$courses$subject_course == "PSYC 1110", ]
  expect_equal(nrow(psyc), 3L)
  expect_lt(psyc$resid_p[1], 0.01)
  expect_gt(b$meta$typical_extra_sd, 10)
  expect_false(any(b$courses$swings))
})

test_that("a course under the listing floor stays in the totals", {
  b <- get_dfw_course_board(df_attempts, modifyList(df01_fall_opt, list(min_window_n = 100L)))
  expect_equal(b$courses$listed, c(FALSE, TRUE, FALSE, TRUE))
  expect_equal(b$totals$n_dfw, 121L)
})

test_that("the spread between sections is read in points beyond chance, over every term in scope", {
  s <- get_dfw_section_spread(df_attempts, df01_fall_opt)
  # Every fall of the two courses with three or more sections. One section a
  # fall is no comparison: PSYC 1110 and MATH 1220 on EA are not read.
  expect_equal(nrow(s$spread_terms), 8L)
  expect_false(any(s$spread_terms$subject_course == "PSYC 1110" | s$spread_terms$campus == "EA"))
  expect_false(any(grepl("instructor", c(names(s$spread_terms), names(s$spread_courses)))))
  math_terms <- s$spread_terms[s$spread_terms$subject_course == "MATH 1220", ]
  expect_equal(math_terms$term, c(201980L, 202080L, 202180L, 202280L))
  # Fall 2022, 2, 4 and 10 of 10.
  expect_equal(c(math_terms$lo_pct[4], math_terms$hi_pct[4], math_terms$n_dfw[4]), c(20, 100, 16))
  expect_equal(math_terms$chisq[4], sum((c(2, 4, 10) - 16 / 3)^2) / (10 * (16 / 30) * (14 / 30)))
  # Fall 2021, 0, 4 and 8 of 10: chi-square 40 / 3 on 2 degrees of freedom,
  # at a rate of 40%, over a weight of 30 - 300 / 30.
  expect_equal(math_terms$spread_weight, rep(20, 4))
  expect_equal(math_terms$spread_var[3], (40 / 3 - 2) * 40 * 60 / 20)
  expect_equal(math_terms$spread_se[3], sqrt(2 * (2 + 2 * (40 / 3 - 2))) * 40 * 60 / 20)
  expect_equal(math_terms$spread_pts[3], sqrt(1360))
  # Fall 2019, 2 of 10 in each section: closer than chance would put them.
  expect_equal(math_terms$spread_var[1], -2 * 20 * 80 / 20)
  expect_equal(math_terms$spread_pts[1], 0)

  courses <- s$spread_courses
  expect_equal(courses$subject_course, c("MATH 1220", "ENGL 1110"))
  math <- courses[1, ]
  # The average is the four falls pooled, the negative ones as they are.
  expect_equal(math$spread_var, mean(math_terms$spread_var))
  expect_equal(math$spread_pts, sqrt(mean(math_terms$spread_var)))
  expect_equal(c(math$terms_read, math$sections_per_term, math$lo_pct, math$hi_pct), c(4, 3, 17.5, 57.5))
  expect_equal(c(math$n_attempts, math$n_dfw), c(120L, 43L))
  expect_equal(courses$direction, c("rising", "steady"))
  expect_equal(c(math$first_spread_pts, courses$spread_pts[2]), c(0, 0))
  expect_gt(math$last_spread_pts, math$spread_pts)

  overall <- s$overall
  expect_equal(overall$terms$n_courses, rep(2L, 4))
  # Fall 2021 pools the two courses by weight. ENGL 1110's four sections, 2,
  # 2, 1 and 1 of 10: chi-square 40 / 51 on 3 degrees of freedom at 15%, over
  # a weight of 40 - 400 / 40.
  engl_2021 <- (40 / 51 - 3) * 15 * 85 / 30
  expect_equal(overall$terms$spread_var[3], (20 * 1360 + 30 * engl_2021) / 50)
  expect_equal(overall$trend$direction, "rising")
  # Every course and term: the eight course-terms pooled by weight, MATH
  # 1220's at 20 and ENGL 1110's at 30, not the mean of the eight.
  engl_terms <- s$spread_terms[s$spread_terms$subject_course == "ENGL 1110", ]
  average <- overall$average
  expect_equal(average$spread_var, (20 * sum(math_terms$spread_var) + 30 * sum(engl_terms$spread_var)) / 200)
  expect_equal(average$spread_pts, sqrt(average$spread_var))
  expect_equal(c(average$n_courses, average$n_course_terms, average$n_attempts, average$n_dfw), c(2L, 8L, 280L, 73L))
  # The lowest sections, MATH 20, 30, 0, 20 and ENGL 30, 20, 10, 0; the
  # highest, MATH 20, 30, 80, 100 and ENGL 30, 30, 20, 10.
  expect_equal(c(average$sections_per_term, average$lo_pct, average$hi_pct), c(3.5, 16.25, 40))
  expect_equal(c(s$meta$min_trend_terms, s$meta$n_without_spread), c(4L, 0L))
})

test_that("sections of different sizes are weighed by what their sizes leave to tell them apart", {
  # The change: MATH 1220 ABQ's first Fall 2021 section is twice the size, its
  # ten passing students copied under new ids: 20, 10 and 10 attempts with 0,
  # 4 and 8 DFW, a rate of 30%.
  first_section <- dplyr::filter(df_attempts, crn == "DFMATHABQ2180a")
  unequal <- dplyr::rows_append(df_attempts, dplyr::mutate(first_section, student_id = paste0(student_id, "_2")))
  s <- get_dfw_section_spread(unequal, df01_fall_opt)
  fall_2021 <- s$spread_terms[s$spread_terms$subject_course == "MATH 1220" & s$spread_terms$term == 202180L, ]
  chisq <- 6^2 / (20 * 0.21) + 1^2 / (10 * 0.21) + 5^2 / (10 * 0.21)
  expect_equal(fall_2021$n_attempts, 40L)
  expect_equal(fall_2021$spread_weight, 40 - (20^2 + 10^2 + 10^2) / 40)
  expect_equal(fall_2021$spread_var, (chisq - 2) * 30 * 70 / 25)
})

test_that("one course's sections can draw together on one campus and apart on another", {
  # The change: MATH 1220 ABQ's falls copied onto campus GA in reverse order
  # (2019 for 2022, 2020 for 2021), so GA's sections start far apart and end
  # together while ABQ's do the opposite.
  falls <- dplyr::filter(df_attempts, subject_course == "MATH 1220", campus == "ABQ",
                         term %in% c(201980L, 202080L, 202180L, 202280L))
  two_campuses <- dplyr::rows_append(
    df_attempts, dplyr::mutate(falls, campus = "GA", term = 201980L + 202280L - term))
  p <- build_dfw_dashboard(two_campuses, test_dims, df01_fall_opt)
  math <- p$sections$spread_courses[p$sections$spread_courses$subject_course == "MATH 1220", ]
  expect_equal(stats::setNames(math$direction, math$campus)[c("ABQ", "GA")], c(ABQ = "rising", GA = "falling"))
  expect_equal(math$spread_pts[math$campus == "GA"], math$spread_pts[math$campus == "ABQ"])
  expect_equal(math$terms_read, c(4L, 4L))
  # Three courses a fall, and the two campuses cancel: no direction overall.
  expect_equal(p$sections$overall$terms$n_courses, rep(3L, 4))
  expect_equal(p$sections$overall$trend$direction, "steady")
  # The page's row for each campus draws that campus's own four terms, GA's
  # the reverse of ABQ's.
  listed <- dfw_spread_course_table(p)
  expect_equal(lengths(listed$series), listed$terms_read)
  on_campus <- function(campus) listed$series[[which(listed$subject_course == "MATH 1220" & listed$campus == campus)]]
  expect_equal(on_campus("ABQ")[1:2], c(0, 0))
  expect_equal(on_campus("GA"), rev(on_campus("ABQ")))
  testthat::local_edition(3)
  expect_snapshot(cat(.dfw_dash_spread(p$sections, 15L), sep = "\n"))
})

test_that("a short history has an average and no direction, and an unreadable term is left out", {
  three_falls <- get_dfw_section_spread(df_attempts, modifyList(df01_fall_opt, list(from_term = 202080L)))
  expect_equal(nrow(three_falls$spread_terms), 6L)
  expect_equal(three_falls$spread_courses$direction, rep("too_few_terms", 2))
  expect_true(all(is.na(three_falls$spread_courses$last_spread_pts)))
  expect_equal(three_falls$spread_courses$terms_read, c(3L, 3L))
  expect_gt(three_falls$spread_courses$spread_pts[1], 0)
  expect_equal(three_falls$overall$trend$direction, "too_few_terms")
  testthat::local_edition(3)
  expect_snapshot(cat(.dfw_dash_spread(three_falls, 15L), sep = "\n"))

  # A campus whose courses have one section a term: nothing to read, no line.
  ea <- get_dfw_section_spread(df_attempts, modifyList(df01_fall_opt, list(campus = "EA")))
  expect_equal(c(nrow(ea$spread_terms), nrow(ea$spread_courses), nrow(ea$overall$terms), nrow(ea$overall$trend),
                 nrow(ea$overall$average)), rep(0L, 5))
  expect_snapshot(cat(.dfw_dash_spread(ea, 15L), sep = "\n"))

  # The change: ENGL 1110's three Fall 2022 DFW attempts removed, so no
  # student in its four sections (9, 9, 10 and 9 attempts) got a DFW; read
  # with sections of 9 or more.
  no_dfw <- dplyr::filter(df_attempts, !(subject_course == "ENGL 1110" & term == 202280L & outcome == "dfw"))
  s <- get_dfw_section_spread(no_dfw, modifyList(df01_fall_opt, list(min_section_n = 9L)))
  expect_false(any(s$spread_terms$subject_course == "ENGL 1110" & s$spread_terms$term == 202280L))
  expect_equal(s$meta$n_without_spread, 1L)
  expect_equal(s$spread_courses$terms_read[s$spread_courses$subject_course == "ENGL 1110"], 3L)
  expect_snapshot(cat(.dfw_dash_spread(s, 15L), sep = "\n"))
})

test_that("the dashboard names colleges and carries the course board's window", {
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  expect_s3_class(p, "dfw_dashboard")
  expect_equal(p$meta$window_terms, c(202080L, 202180L, 202280L))
  expect_equal(unique(p$courses$courses$college_name[p$courses$courses$college == "UC"]),
               unname(college_code_names(test_dims)["UC"]))
  expect_equal(p$meta$level, "lower")
})

test_that("the DFW Rates page's scope has one form, and the page opens on a scope it can ask for", {
  scope <- dfw_rates_page_scope("fall", c("EA", "ABQ"), "201980", "202180")
  expect_identical(scope, list(term_type = "fall", campus = c("ABQ", "EA"), from_term = 201980L, to_term = 202180L))
  # The same campuses in another order, or named twice, are the same scope.
  expect_identical(dfw_rates_page_scope("fall", c("ABQ", "EA", "ABQ"), 201980L, 202180L), scope)
  # No campus picked is every campus, however the browser says it.
  expect_null(dfw_rates_page_scope("fall", character(0), 201980, 202180)$campus)
  expect_null(dfw_rates_page_scope("fall", NULL, 201980, 202180)$campus)
  expect_error(dfw_rates_page_scope(c("fall", "spring"), NULL, 201980, 202180), "one term type")
  expect_error(dfw_rates_page_scope("fall", NULL, "first", 202180), "a first and a last term")
  expect_error(dfw_rates_page_scope("fall", NULL, 202180, 201980), "first term is after its last")

  # It opens on fall, the default campuses it offers and every term it offers.
  opens_on <- dfw_rates_default_scope(c("ZZ", CEDAR_CAMPUS_DEFAULT), c(202180L, 201980L, 202080L, 202080L))
  expect_identical(opens_on, list(term_type = "fall", campus = CEDAR_CAMPUS_DEFAULT,
                                  from_term = 201980L, to_term = 202180L))
  expect_identical(dfw_rates_default_scope("ZZ", 202080L)$campus, character(0))
  expect_error(dfw_rates_default_scope("ABQ", integer(0)), "graded terms it offers")

  # DF01 as the page opens on it: every term it holds, so the same rates as
  # the whole history read for those campuses.
  opens_on <- dfw_rates_default_scope(unique(df_attempts$campus), unique(df_attempts$term))
  scope <- dfw_rates_page_scope(opens_on$term_type, opens_on$campus, opens_on$from_term, opens_on$to_term)
  built <- build_dfw_dashboard(df_attempts, test_dims, dfw_rates_page_opt(scope, df01_edges))
  expect_identical(built$meta[c("term_type", "campus", "from_term", "to_term")], scope)
  whole <- build_dfw_dashboard(df_attempts, test_dims, c(df01_fall_opt, list(campus = scope$campus)))
  expect_equal(built$overall$terms, whole$overall$terms)
  expect_equal(built$courses$courses, whole$courses$courses)
})

test_that("the DFW dashboard's text preview", {
  testthat::local_edition(3)
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  expect_snapshot(cat(format_dfw_dashboard(p)))
})

test_that("the course board carries each course's term series", {
  b <- get_dfw_course_board(df_attempts, df01_fall_opt)
  math <- b$terms[b$terms$subject_course == "MATH 1220" & b$terms$campus == "ABQ", ]
  expect_equal(math$term, c(201980L, 202080L, 202180L, 202280L))
  expect_equal(math$n_dfw, c(6L, 9L, 12L, 16L))
  expect_true(all(math$in_trend))
  expect_setequal(paste(b$terms$subject_course, b$terms$campus), paste(b$courses$subject_course, b$courses$campus))
})

test_that("the page's figures split the totals they stand for", {
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  bars <- prepare_dfw_overall_plot_data(p)
  expect_equal(levels(bars$kind), unname(DFW_GRADE_KIND_LABELS))
  by_term <- dplyr::summarize(dplyr::group_by(bars, term), pts = sum(pts), n = sum(n), rate = dplyr::first(dfw_pct),
                              n_dfw = dplyr::first(n_dfw))
  expect_equal(by_term$pts, by_term$rate)
  expect_equal(by_term$n, by_term$n_dfw)

  conc <- dfw_concentration_parts(p)
  # MATH 1220 (ABQ) alone holds 37 of 121, past a quarter; PSYC 1110 takes it past half.
  expect_equal(conc$n, c(37L, 36L, 48L))
  expect_equal(conc$n_courses, c(1L, 1L, 2L))

  changes <- dfw_change_counts(p)
  expect_equal(changes$n, c(1L, 1L, 1L))
  expect_equal(changes$n_listed, rep(4L, 3))

  # MATH 1220 (ABQ) is spreading and ENGL 1110 (ABQ) shows no clear change.
  directions <- dfw_spread_direction_parts(p)
  expect_equal(directions$n, c(1L, 0L, 1L))
  expect_equal(attr(directions, "n_short"), 0L)
  spread <- dfw_spread_finding(p)
  expect_equal(c(spread$n_courses, spread$n_course_terms, spread$first_term, spread$last_term),
               c(2L, 8L, 201980L, 202280L))
  expect_equal(c(spread$spread_pts, spread$lo_pct, spread$hi_pct),
               c(p$sections$overall$average$spread_pts, 16.25, 40))
})

test_that("a scope too short for a direction, or with no sections to compare, lists no course", {
  # Three falls: both courses have an average and neither a direction.
  three_falls <- build_dfw_dashboard(df_attempts, test_dims, modifyList(df01_fall_opt, list(from_term = 202080L)))
  directions <- dfw_spread_direction_parts(three_falls)
  expect_equal(directions$n, c(0L, 0L, 0L))
  expect_equal(c(attr(directions, "n_short"), attr(directions, "min_trend_terms")), c(2L, 4L))
  expect_equal(dfw_spread_finding(three_falls)$n_course_terms, 6L)
  expect_equal(nrow(dfw_spread_course_table(three_falls)), 0L)
  expect_equal(nrow(prepare_dfw_spread_term_plot_data(three_falls)), 3L)

  # EA's courses have one section a fall: nothing to read, and nothing fails.
  ea <- build_dfw_dashboard(df_attempts, test_dims, modifyList(df01_fall_opt, list(campus = "EA")))
  expect_equal(dfw_spread_finding(ea)$n_courses, 0L)
  expect_equal(dfw_spread_direction_parts(ea)$n, c(0L, 0L, 0L))
  expect_equal(c(nrow(dfw_spread_course_table(ea)), nrow(prepare_dfw_spread_term_plot_data(ea)),
                 nrow(prepare_dfw_spread_course_bars(ea))), c(0L, 0L, 0L))
})

test_that("the page's tables and charts keep each course's own series", {
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  courses <- dfw_course_table(p)
  expect_equal(courses$series[[1]], c(20, 30, 40, 160 / 3))
  expect_equal(courses$cum_pct[nrow(courses)], 100)
  expect_equal(dfw_swing_table(p)$subject_course, "PSYC 1110")

  # Furthest apart first; MATH 1220's sections, 0 and 0 points apart in the
  # falls they sat closer than chance, then Fall 2021's sqrt(1360).
  spread <- dfw_spread_course_table(p)
  expect_equal(spread$subject_course, c("MATH 1220", "ENGL 1110"))
  expect_equal(spread$series[[1]][1:3], c(0, 0, sqrt(1360)))
  expect_equal(c(spread$lo_pct[1], spread$hi_pct[1], spread$terms_read[1]), c(17.5, 57.5, 4))
  expect_equal(spread$direction, c("Spreading", "No clear change"))
  bars <- prepare_dfw_spread_course_bars(p)
  expect_equal(bars$label, c("MATH 1220 (ABQ)", "ENGL 1110 (ABQ)"))
  expect_equal(bars$spread_pts, spread$spread_pts)
  expect_equal(prepare_dfw_spread_term_plot_data(p)$n_courses, rep(2L, 4))

  slopes <- prepare_dfw_slope_plot_data(p)
  expect_equal(slopes$label, c("MATH 1220 (ABQ)", "ENGL 1110 (ABQ)"))
  expect_equal(as.character(slopes$direction), c("Rising", "Falling"))

  campus <- dfw_group_table(p$by_campus, "campus")
  expect_equal(campus$campus, c("ABQ", "EA"))
  expect_equal(lengths(campus$series), c(4L, 4L))
})

test_that("the page's charts draw a trace per part they show", {
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  names_of <- function(plot) vapply(plotly::plotly_build(plot)$x$data, function(t) t$name, character(1))
  expect_equal(names_of(plot_dfw_overall(prepare_dfw_overall_plot_data(p))), unname(DFW_GRADE_KIND_LABELS))
  expect_setequal(names_of(plot_dfw_course_bars(prepare_dfw_course_bars(p))), c("Rising", "Falling", "Steady"))
  expect_equal(names_of(plot_dfw_slopes(prepare_dfw_slope_plot_data(p))), c("Rising", "Falling"))
  expect_equal(names_of(plot_dfw_spread_terms(prepare_dfw_spread_term_plot_data(p))), "Every course")
  expect_equal(names_of(plot_dfw_spread_course_bars(prepare_dfw_spread_course_bars(p))),
               c("Spreading", "No clear change"))
})
