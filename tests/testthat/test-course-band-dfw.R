# get_course_band_dfw() (R/cones/course-band-dfw.R): is a course harder on its
# lowest-GPA students than their other courses are, by more than it is for
# its other students? BD01 is in fixtures/scenario_tables.R, with its counts.

test_that("BD01: a band's excess is its rate in the course less its rate in the rest of the term", {
  r <- get_course_band_dfw(bd01$attempts, bd01$student_terms, list(data_edges = bd01$edges, campus = "ABQ"))
  gate <- r$courses[r$courses$subject_course == "GATE 101", ]
  expect_equal(c(gate$low_attempts, gate$rest_attempts, gate$low_other_attempts), c(30L, 30L, 30L))
  expect_equal(c(gate$low_dfw_pct, gate$low_other_dfw_pct, gate$low_excess_pts), c(60, 20, 40))
  expect_equal(c(gate$rest_dfw_pct, gate$rest_other_dfw_pct, gate$rest_excess_pts), c(20, 10, 10))
  expect_equal(gate$gap_pts, 30)
  expect_equal(gate$gap_se, 100 * sqrt(0.65 / 30))
  expect_equal(gate$verdict, "harder")
  # The same students the other way round: OTHR 200 is where they do better
  # than in the rest of their term, by more than its other students do.
  othr <- r$courses[r$courses$subject_course == "OTHR 200", ]
  expect_equal(c(othr$low_excess_pts, othr$rest_excess_pts, othr$gap_pts), c(-40, -10, -30))
  expect_equal(othr$verdict, "easier")
  expect_identical(r$courses$subject_course, c("GATE 101", "OTHR 200"))
  expect_equal(r$meta$low_band, "below 2.5")
  # 21 seats a fall are banded (EA1 among them); three first-term students
  # and one invalid timeline a fall are left out and counted.
  expect_equal(c(r$meta$n_banded, r$meta$n_no_band, r$meta$n_invalid), c(63L, 9L, 3L))
  expect_equal(r$bands$excess_pts[r$bands$subject_course == "GATE 101" & r$bands$band == "below 2.5"], 40)
})

test_that("BD01: a course is read on the campus that taught it, at its size and in its terms", {
  every <- get_course_band_dfw(bd01$attempts, bd01$student_terms, list(data_edges = bd01$edges))
  # EA's GATE 101 has three low-band attempts and no other band: in the band
  # rows, never a course row.
  expect_false("EA" %in% every$courses$campus)
  expect_true("EA" %in% every$bands$campus)
  # ABQ's counts are untouched by EA's students.
  expect_equal(every$courses$low_attempts[every$courses$subject_course == "GATE 101"], 30L)
  # One fall is 10 attempts a side: under 30, both courses are small.
  one <- get_course_band_dfw(bd01$attempts, bd01$student_terms, list(data_edges = bd01$edges, term = 202080L))
  expect_equal(nrow(one$courses), 0L)
  expect_equal(one$meta$n_courses_small, 2L)
  # Read at 10 a side, one fall's gap is inside chance.
  small <- get_course_band_dfw(bd01$attempts, bd01$student_terms,
                               list(data_edges = bd01$edges, term = 202080L, min_n = 10L))
  expect_equal(small$courses$verdict, c("no_difference", "no_difference"))
  # The graded edge bounds the terms.
  early <- get_course_band_dfw(bd01$attempts, bd01$student_terms,
                               list(data_edges = list(last_graded = 202180L), min_n = 10L))
  expect_equal(early$meta$terms, c(202080L, 202180L))
})

test_that("BD01: first-term students are read by high-school GPA band on request", {
  r <- get_course_band_dfw(bd01$attempts, bd01$student_terms,
                           list(data_edges = bd01$edges, band_by = "hs", min_n = 3L), bd01$applicants)
  expect_equal(r$meta$low_band, "2.75 or lower")
  # F1 and F2 a fall are banded; F3 has no high-school GPA on file.
  expect_equal(c(r$meta$n_banded, r$meta$n_no_band), c(6L, 3L))
  gate <- r$courses[r$courses$subject_course == "GATE 101", ]
  expect_equal(c(gate$low_dfw_pct, gate$low_other_dfw_pct, gate$rest_dfw_pct), c(100, 0, 0))
  expect_error(get_course_band_dfw(bd01$attempts, bd01$student_terms, list(data_edges = bd01$edges, band_by = "hs")),
               "applicants")
})

test_that("get_course_band_dfw() stops without its edge, its columns or a known band", {
  expect_error(get_course_band_dfw(bd01$attempts, bd01$student_terms, list()), "graded edge")
  expect_error(get_course_band_dfw(bd01$attempts %>% select(-campus), bd01$student_terms,
                                   list(data_edges = bd01$edges)), "campus")
  expect_error(get_course_band_dfw(bd01$attempts, bd01$student_terms, list(data_edges = bd01$edges, band_by = "act")),
               "band_by")
  expect_error(get_course_band_dfw(bd01$attempts, bd01$student_terms, list(data_edges = bd01$edges, term = 201980L)),
               "no graded attempt")
})

# ISSUES M67: the Retention page's section read every student in a course,
# whatever level the page was set to, and read the page's home-campus control
# as the campus that taught the course.
test_that("BD02: the students read are those of the level and home campus asked for", {
  band_dfw <- function(opt, applicants = NULL) {
    get_course_band_dfw(bd02$attempts, bd02$student_terms, c(list(data_edges = bd02$edges), opt), applicants)
  }
  gate_of <- function(r) r$courses[r$courses$subject_course == "GATE 101" & r$courses$campus == "ABQ", ]

  # Undergraduates of home campus ABQ: BD01's seats and BD01's numbers.
  page <- band_dfw(list(student_level = "UG", student_campus = "ABQ"))
  gate <- gate_of(page)
  expect_equal(c(gate$low_attempts, gate$rest_attempts), c(30L, 30L))
  expect_equal(c(gate$low_dfw_pct, gate$low_other_dfw_pct, gate$rest_dfw_pct, gate$rest_other_dfw_pct),
               c(60, 20, 20, 10))
  expect_equal(gate$gap_pts, 30)
  expect_equal(gate$verdict, "harder")
  expect_equal(c(page$meta$n_banded, page$meta$n_out_of_scope), c(63L, 61L))
  # A level is the term's: S1 was an undergraduate one fall and a graduate
  # student the next, and the course of the second is not read.
  expect_false("SEMR 600" %in% page$bands$subject_course)
  # Home campus is not the campus that taught the course: EA1's GATE 101,
  # taught on EA, is read, and no campus that taught a course is left out.
  expect_true("EA" %in% page$bands$campus)
  expect_null(page$meta$campus)

  # Every level: ten graduate seats a fall join the lowest band.
  every_level <- band_dfw(list(student_campus = "ABQ"))
  expect_true("SEMR 600" %in% every_level$bands$subject_course)
  gate <- gate_of(every_level)
  expect_equal(c(gate$low_attempts, gate$low_dfw_pct, gate$low_other_dfw_pct, gate$gap_pts), c(60, 30, 60, -40))
  expect_equal(gate$verdict, "easier")

  # Every home campus: ten EA-home seats a fall join the course's other students.
  gate <- gate_of(band_dfw(list(student_level = "UG")))
  expect_equal(c(gate$rest_attempts, gate$rest_dfw_pct, gate$rest_other_dfw_pct, gate$gap_pts), c(60, 60, 5, -15))
  expect_equal(gate$verdict, "no_difference")

  # A scope with no student is an empty result over the same terms and scale.
  nobody <- band_dfw(list(student_level = "LW"))
  expect_equal(c(nrow(nobody$courses), nrow(nobody$bands), nobody$meta$n_banded), c(0L, 0L, 0L))
  expect_equal(nobody$meta$low_band, "below 2.5")
  expect_equal(nobody$meta$terms, c(202080L, 202180L, 202280L))
  # No graduate seat is a first-term student: nobody is banded by high-school
  # GPA, and the scale's lowest band is still the lowest.
  grads <- band_dfw(list(student_level = "GR", band_by = "hs"), bd02$applicants)
  expect_equal(grads$meta$low_band, "2.75 or lower")
  expect_equal(c(grads$meta$n_banded, nrow(grads$courses)), c(0L, 0L))

  # A scope is read from the student-terms' own level and home campus.
  expect_error(get_course_band_dfw(bd01$attempts, bd01$student_terms,
                                   list(data_edges = bd01$edges, student_level = "UG")),
               "student_terms lacks enrolled, student_level, student_campus")
})

test_that("BD02: the page's lists, their count by chance and the sentence", {
  # The page's scope: its student level, and its campus as the home campus.
  opt <- list(term_type = "fall", student_level = "UG", campus = "ABQ", data_edges = bd02$edges)
  r <- retention_dashboard_band_courses(bd02$attempts, bd02$student_terms, NULL, opt)
  expect_equal(r$harder$subject_course, "GATE 101")
  expect_equal(r$easier$subject_course, "OTHR 200")
  expect_equal(c(r$meta$student_level, r$meta$student_campus), c("UG", "ABQ"))
  expect_true("EA" %in% r$bands$campus)
  # 30 attempts at a 30-point gap: 9 more DFWs than at the other students' excess.
  expect_equal(r$harder$excess_dfw, 9)
  expect_equal(r$meta$n_by_chance, 2 * stats::pnorm(-2))
  # The latest two falls only: 20 attempts a side, under the guard.
  two <- retention_dashboard_band_courses(bd02$attempts, bd02$student_terms, NULL, c(opt, list(band_terms = 2L)))
  expect_equal(two$meta$terms, c(202180L, 202280L))
  expect_equal(two$meta$n_courses, 0L)
  hs <- retention_dashboard_band_courses(bd02$attempts, bd02$student_terms, bd02$applicants,
                                         c(opt, list(band_by = "hs", min_n = 3L)))
  testthat::local_edition(3)
  expect_snapshot(cat(retention_band_sentence(r), retention_band_sentence(two), retention_band_sentence(hs), sep = "\n"))
  # Every course with a verdict is counted, whatever the lists show: with 20
  # harder courses the sentence says 20 and that 15 are listed.
  expect_equal(c(r$meta$n_harder, r$meta$n_easier), c(1L, 1L))
  many <- r; many$meta$n_harder <- 20L
  expect_snapshot(cat(retention_band_sentence(many)))
  expect_error(retention_dashboard_band_courses(bd02$attempts, bd02$student_terms, NULL,
                                                list(term_type = "spring", data_edges = bd02$edges)), "no graded spring")
})
