# SS01 (fixtures/scenario_tables.R): a spring's students in the summer after, and in the fall.

test_that("SS01: summer credits by band, and who was back in the fall or had finished", {
  r <- get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees, ss01$opt)
  s22 <- r$by_band[r$by_band$term == 202210L, ]
  expect_equal(as.character(s22$band), c("No course here", "1 to 3 credits", "4 to 6 credits"))
  expect_equal(s22$n, c(4L, 2L, 1L))
  expect_equal(s22$n_readable, c(4L, 2L, 1L))
  # No course: SS-D and SS-F enrolled, SS-H awarded a degree that spring, SS-C
  # not back. 1 to 3: SS-B enrolled, SS-E awarded a degree that summer.
  expect_equal(s22$n_back, c(3L, 2L, 1L))
  # Spring 2023's fall is past the settled edge: counted, not read.
  s23 <- r$by_band[r$by_band$term == 202310L, ]
  expect_equal(c(s23$n, s23$n_readable, s23$n_back), c(1L, 0L, 0L))
  expect_equal(c(r$meta$n_students, r$meta$n_took), c(8L, 3L))
})

test_that("SS01: behind on credits after the spring, and caught up by the summer's completed credits", {
  r <- get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees, ss01$opt)
  # Only Spring 2022's summer is graded. SS-F's total is not whole. Behind 30:
  # SS-A, SS-B (24) and SS-C (20); SS-A's 6 summer credits reach it, SS-B's 3 do not.
  expect_equal(r$pace$term, 202210L)
  # SS-H finished that spring: left out, not behind at 20.
  expect_equal(unlist(r$pace[c("n_finished", "n_known", "n_unknown", "n_behind", "n_behind_summer", "n_caught_up")]),
               c(n_finished = 1L, n_known = 5L, n_unknown = 1L, n_behind = 3L, n_behind_summer = 2L, n_caught_up = 1L))
  # Attempted is not completed: SS-E's 3 attempted credits would not have counted.
  slower <- utils::modifyList(ss01$opt, list(pace_credits = 21))
  expect_equal(get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees,
                                       slower)$pace$n_caught_up, 0L)
  none <- ss01$opt
  none$pace_credits <- NULL
  expect_null(get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees, none)$pace)
})

test_that("SS01: the courses are the summer takers', or only those of the students behind", {
  r <- get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees, ss01$opt)
  expect_equal(r$courses$subject_course, c("MATH 101", "HIST 101"))
  expect_equal(r$courses$campus, c("ABQ", "EA"))
  expect_equal(r$courses$share_pct, c(200 / 3, 100 / 3))
  behind <- get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees,
                                    c(ss01$opt, list(courses_for = "behind")))
  expect_equal(behind$courses$subject_course, "MATH 101")
  expect_equal(c(behind$courses$n_students, behind$meta$n_course_students), c(2L, 2L))
})

test_that("get_summer_after_spring() stops on a repeated student-term, a term that is not a spring, or a missing edge", {
  run <- function(who = ss01$spring_students, opt = ss01$opt) {
    get_summer_after_spring(who, ss01$student_terms, ss01$attempts, ss01$degrees, opt)
  }
  expect_error(run(dplyr::bind_rows(ss01$spring_students, ss01$spring_students)), "twice")
  fall <- ss01$spring_students
  fall$term <- 202280L
  expect_error(run(fall), "spring")
  expect_error(run(ss01$spring_students["student_id"]), "lacks")
  no_edge <- ss01$opt
  no_edge$data_edges <- list(last_enrolled_complete = 202310L)
  expect_error(run(opt = no_edge), "edges")
  no_pace <- ss01$opt
  no_pace$pace_credits <- NULL
  expect_error(run(opt = c(no_pace, list(courses_for = "behind"))), "courses_for")
})

test_that("SS01: the page's rows: back in the fall by taking a summer course, and catching up by spring", {
  r <- get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees, ss01$opt)
  by_taking <- summer_return_by_taking(r, min_n = 1L)
  # Spring 2022 only (2023's fall is not settled): 3 of 7 took a course, all back; 3 of the other 4.
  expect_equal(by_taking$term, 202210L)
  expect_equal(c(by_taking$n, by_taking$n_took), c(7L, 3L))
  expect_equal(c(by_taking$back_took_pct, by_taking$back_none_pct), c(100, 75))
  expect_true(is.na(summer_return_by_taking(r, min_n = 4L)$back_took_pct))
  caught <- summer_catch_up_by_term(r)
  expect_equal(unlist(caught[c("n_behind", "n_no_summer", "n_still_behind", "n_caught_up")]),
               c(n_behind = 3L, n_no_summer = 1L, n_still_behind = 1L, n_caught_up = 1L))
})

test_that("SS01: the two sections' words and figures", {
  testthat::local_edition(3)
  r <- get_summer_after_spring(ss01$spring_students, ss01$student_terms, ss01$attempts, ss01$degrees, ss01$opt)
  by_taking <- summer_return_by_taking(r, min_n = 1L)
  caught <- summer_catch_up_by_term(r)
  expect_snapshot(cat(summer_return_sentence(by_taking), summer_catch_up_sentence(caught, 15), sep = "\n"))
  expect_equal(summer_return_sentence(summer_return_by_taking(r, min_n = 99L)), character(0))
  lines <- plotly::plotly_build(plot_summer_return(by_taking))
  expect_equal(vapply(lines$x$data, function(d) d$name, character(1)), c("Took a summer course", "Did not"))
  expect_equal(as.character(lines$x$data[[1]]$x), "Spring 2022")
  bars <- plotly::plotly_build(plot_summer_catch_up(caught))
  expect_equal(vapply(bars$x$data, function(d) d$name, character(1)), unname(SUMMER_CATCH_UP_PARTS))
  expect_equal(vapply(bars$x$data, function(d) as.numeric(d$y), numeric(1)), c(1, 1, 1))
})
