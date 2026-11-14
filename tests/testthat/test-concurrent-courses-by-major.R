# get_concurrent_courses_by_major() on CM01: CHEM 1215 on ABQ and EA, Fall
# 2020 and Fall 2021, the settled edge Fall 2021. The expected values are
# worked out beside the rows in fixtures/designed_test_data.R.

test_that("each of the largest majors gets its own list, and the rest are All other majors", {
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 2, min_course_n = 1,
              data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  abq <- dplyr::filter(r$groups, campus == "ABQ")
  expect_equal(abq$group, c("Nursing (pre-major)", "Mechanical Engineering", "Undecided",
                            "Biology", "Nursing", "All other majors"))
  expect_equal(abq$group_rank, 1:6)
  expect_equal(abq$n_student_terms, c(5L, 4L, 3L, 2L, 2L, 2L))
  expect_equal(abq$n_students, c(5L, 3L, 3L, 2L, 2L, 2L))
  expect_equal(abq$n_majors, c(1L, 1L, 1L, 1L, 1L, 2L))
  expect_equal(r$meta$terms$terms[r$meta$terms$campus == "ABQ"][[1]], c(202080L, 202180L))
})

test_that("a share is of the group's student-terms, same campus and term, registered rows only", {
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 2, min_course_n = 1,
              data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  pre <- dplyr::filter(r$courses, campus == "ABQ", group == "Nursing (pre-major)")
  # CM_N4's PSYC 1110 is at EA and CM_N5's ENGL 1120 an early drop: neither counts.
  expect_equal(pre$subject_course, c("BIOL 2210", "ENGL 1120", "PSYC 1110"))
  expect_equal(pre$n_student_terms, c(4L, 2L, 1L))
  expect_equal(pre$pct, c(80, 40, 20))
  me <- dplyr::filter(r$courses, campus == "ABQ", group == "Mechanical Engineering")
  # CM_M3 in two falls is two student-terms.
  expect_equal(me$subject_course, c("MATH 1512", "PHYS 1310"))
  expect_equal(me$pct, c(75, 50))
  other <- dplyr::filter(r$courses, campus == "ABQ", group == "All other majors")
  expect_equal(other$subject_course, c("MATH 1512", "PSYC 1110"))
  expect_equal(other$pct, c(50, 50))
  expect_false("CHEM 1215" %in% r$courses$subject_course)
})

test_that("the course's own lab is read once per campus and kept out of the lists", {
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 2, min_course_n = 1,
              data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  expect_equal(r$lab$campus, c("ABQ", "EA"))
  expect_equal(r$lab$lab_course, c("CHEM 1215L", "CHEM 1215L"))
  expect_equal(r$lab$n_student_terms, c(4L, 1L))
  expect_equal(r$lab$course_student_terms, c(18L, 2L))
  expect_equal(r$lab$pct, c(400 / 18, 50))
  expect_false("CHEM 1215L" %in% r$courses$subject_course)
  few <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims,
                                         utils::modifyList(opt, list(min_course_n = 2)))
  expect_equal(few$lab$campus, "ABQ")
})

test_that("each campus is read apart", {
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 2, min_course_n = 1,
              data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  ea <- dplyr::filter(r$groups, campus == "EA")
  expect_equal(ea$group, "All other majors")
  expect_equal(ea$n_student_terms, 2L)
  ea_courses <- dplyr::filter(r$courses, campus == "EA")
  expect_equal(ea_courses$subject_course, "ENGL 1110")
  expect_equal(ea_courses$pct, 100)
  expect_false("ENGL 1110" %in% r$courses$subject_course[r$courses$campus == "ABQ" &
                                                          r$courses$group == "Nursing (pre-major)"])
  only_abq <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims,
                                              utils::modifyList(opt, list(campus = "ABQ")))
  expect_equal(unique(only_abq$groups$campus), "ABQ")
})

test_that("a major under min_n folds into All other majors", {
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 3, min_course_n = 1,
              data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  abq <- dplyr::filter(r$groups, campus == "ABQ")
  expect_equal(abq$group, c("Nursing (pre-major)", "Mechanical Engineering", "Undecided", "All other majors"))
  expect_equal(abq$n_student_terms[4], 6L)
  expect_equal(abq$n_majors[4], 4L)
  expect_equal(sum(abq$n_student_terms), 18L)
})

test_that("the window is the course's last terms of one type, up to the settled edge", {
  opt <- list(course = "CHEM 1215", term_type = "fall", min_n = 2, min_course_n = 1, data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  # Three falls by default: Fall 2019 joins (CM_O1); Fall 2022 is past the edge (CM_L1).
  expect_equal(r$meta$terms$terms[r$meta$terms$campus == "ABQ"][[1]], c(201980L, 202080L, 202180L))
  abq <- dplyr::filter(r$groups, campus == "ABQ")
  expect_equal(abq$group[1:2], c("Mechanical Engineering", "Nursing (pre-major)"))
  expect_equal(abq$n_student_terms[1:2], c(5L, 5L))
  me <- dplyr::filter(r$courses, campus == "ABQ", group == "Mechanical Engineering")
  expect_equal(me$pct[me$subject_course == "MATH 1512"], 80)
  spring <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims,
                                            utils::modifyList(opt, list(term_type = "spring")))
  # CM_S1 alone, Spring 2021.
  expect_equal(spring$groups$n_student_terms, 1L)
  expect_equal(spring$meta$terms$terms[[1]], 202110L)
})

test_that("min_course_n and n_courses limit the listed courses", {
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 2, min_course_n = 2,
              n_courses = 1, data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  abq <- dplyr::filter(r$courses, campus == "ABQ")
  expect_equal(abq$group, c("Nursing (pre-major)", "Mechanical Engineering", "Undecided", "Biology"))
  expect_equal(abq$subject_course, c("BIOL 2210", "MATH 1512", "ENGL 1110", "BIOL 2110C"))
})

test_that("it stops on a missing option, edge or student-term row", {
  opt <- list(course = "CHEM 1215", term_type = "fall", data_edges = cm01_edges)
  expect_error(get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims,
                                               utils::modifyList(opt, list(course = NULL))), "opt\\$course")
  expect_error(get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims,
                                               utils::modifyList(opt, list(term_type = "winter"))), "term_type")
  no_edge <- opt
  no_edge$data_edges <- list(last_graded = 202180L)
  expect_error(get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, no_edge),
               "last_enrolled_complete")
  expect_error(get_concurrent_courses_by_major(test_students_cm,
                                               dplyr::filter(test_student_terms_cm, student_id != "CM_N1"),
                                               test_dims, opt), "no row on cedar_student_terms")
})

test_that("the text preview reads the lists by campus", {
  testthat::local_edition(3)
  opt <- list(course = "CHEM 1215", term_type = "fall", n_terms = 2, min_n = 2, min_course_n = 1,
              data_edges = cm01_edges)
  r <- get_concurrent_courses_by_major(test_students_cm, test_student_terms_cm, test_dims, opt)
  expect_snapshot(cat(format_concurrent_courses_by_major(r), sep = "\n"))
})
