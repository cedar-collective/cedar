# SG01 (fixtures/scenario_tables.R): spring students who finish in the summer.

test_that("SG01: who finished in the summer, the credits they took then and in which courses", {
  r <- get_summer_finishers(sg01$student_terms, sg01$degrees, sg01$attempts, sg01$opt)
  s22 <- r$by_term[r$by_term$term == 202210L, ]
  expect_equal(as.character(s22$band), c("No course here", "1 to 3 credits", "4 to 6 credits"))
  expect_equal(s22$n, c(1L, 1L, 1L))
  expect_true(all(s22$basis == "awarded") && all(s22$finish_term == 202260L))
  # Spring 2023: an application, the summer not posted or graded; no summer course on record.
  s23 <- r$by_term[r$by_term$term == 202310L, ]
  expect_equal(c(s23$n, as.character(s23$basis), as.character(s23$band)), c("1", "applied", "No course here"))
  # Courses: graded summers only, by course and teaching campus, as a share of those summers' finishers.
  expect_equal(r$meta$course_terms, 202260L)
  expect_equal(r$courses$subject_course, c("MATH 101", "HIST 101"))
  expect_equal(r$courses$campus, c("ABQ", "EA"))
  expect_equal(r$courses$n_students, c(2L, 1L))
  expect_equal(r$courses$share_pct, c(200 / 3, 100 / 3))
  expect_equal(c(r$meta$n_finishers, r$meta$n_course_finishers), c(4L, 3L))
  # The course guard, and the level scope (S-J, a graduate student, alone).
  expect_equal(get_summer_finishers(sg01$student_terms, sg01$degrees, sg01$attempts,
                                    utils::modifyList(sg01$opt, list(min_n = 2L)))$courses$subject_course, "MATH 101")
  gr <- get_summer_finishers(sg01$student_terms, sg01$degrees, sg01$attempts, utils::modifyList(sg01$opt, list(student_level = "GR")))
  expect_equal(gr$meta$n_finishers, 1L)
  expect_error(get_summer_finishers(sg01$student_terms["student_id"], sg01$degrees, sg01$attempts, sg01$opt), "lacks")
  # One bar a finishing term, a trace a credit band.
  fig <- plotly::plotly_build(plot_summer_finishers(r))
  expect_equal(vapply(fig$x$data, function(d) d$name, character(1)), SUMMER_CREDIT_BANDS)
  expect_equal(as.character(fig$x$data[[1]]$x), c("Summer 2022", "Summer 2023<br>(applied)"))
})
