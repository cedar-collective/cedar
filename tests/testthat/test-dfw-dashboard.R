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

test_that("section spread tests course-terms with three sections and finds the uneven ones", {
  s <- get_dfw_section_spread(df_attempts, df01_fall_opt)
  ct <- s$course_terms
  expect_equal(nrow(ct), 6L)
  expect_equal(ct$uneven[ct$subject_course == "MATH 1220"], c(FALSE, TRUE, TRUE))
  expect_false(any(ct$uneven[ct$subject_course == "ENGL 1110"]))
  # One section a fall is no comparison: neither course is tested.
  expect_false(any(ct$subject_course == "PSYC 1110" | ct$campus == "EA"))
  fall_2022 <- ct[ct$subject_course == "MATH 1220" & ct$term == 202280L, ]
  expect_equal(c(fall_2022$lo_pct, fall_2022$hi_pct, fall_2022$n_dfw), c(20, 100, 16))
  expect_equal(fall_2022$chisq, sum((c(2, 4, 10) - 16 / 3)^2) / (10 * (16 / 30) * (14 / 30)))
  math <- s$sections[s$sections$subject_course == "MATH 1220" & s$sections$term == 202180L, ]
  expect_equal(math$dfw_pct, c(80, 40, 0))
  expect_equal(math$position, c("above", "within", "below"))
  courses <- s$courses
  expect_equal(paste(courses$subject_course, courses$terms_uneven, courses$terms_tested),
               c("MATH 1220 2 3", "ENGL 1110 0 3"))
  expect_equal(courses$sections_above[courses$subject_course == "MATH 1220"], 2L)
  expect_false(any(grepl("instructor", c(names(s$sections), names(s$course_terms), names(s$courses)))))
})

test_that("the dashboard names colleges and agrees on its window", {
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  expect_s3_class(p, "dfw_dashboard")
  expect_equal(p$meta$window_terms, p$sections$meta$window_terms)
  expect_equal(unique(p$courses$courses$college_name[p$courses$courses$college == "UC"]),
               unname(college_code_names(test_dims)["UC"]))
  expect_equal(p$meta$level, "lower")
})

test_that("the DFW dashboard's text preview", {
  testthat::local_edition(3)
  p <- build_dfw_dashboard(df_attempts, test_dims, df01_fall_opt)
  expect_snapshot(cat(format_dfw_dashboard(p)))
})
