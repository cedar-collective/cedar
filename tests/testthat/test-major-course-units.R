# get_major_course_units() (R/cones/major-course-units.R): which units teach
# the courses a major's students take.
#
# Fixtures (setup.R): the student-term tables built by the production builder
# over ST01, MC02 and RW01, with units attached, beside each one's class list.
#
# ST01, HIST majors, settled edge 202110 (every ST01 term):
#   202010 ABQ  HIST 1110 ST_A, ST_B, ST_C, ST_D, ST_E, ST_F (two rows), ST_H, ST_J
#               ENGL 1110 ST_H            MATH 1215 ST_H (DW: a late drop, a seat held)
#   202110 ABQ  HIST 1110 ST_I
#   ST_G (major AA, no unit) and the SPAN majors (ST_K, and ST_A/B/C/D in later
#   terms) are not members. 9 member student-terms, 9 students.
# MC02, SPAN majors, settled edge 202110:
#   202010 ABQ  SPAN: MC_A1 (101, 101L), MC_A2 (101, 101L), MC_A3, MC_A4 -> 6 regs, 4 students
#   202010 GA   SPAN: MC_G1, MC_G2
#   202080 ABQ  SPAN: MC_A1, MC_A2, MC_A4, MC_G1    PHIL: MC_A3
#   202110 ABQ  SPAN: MC_A1
# RW01, SPAN majors, settled edge 202080, last enrolled 202110:
#   202080 ABQ  ENGL 1110 RW_H
#   202110 ABQ  HIST 2110 RW_A, RW_F, RW_G (RW_B waitlisted: not enrolled)
#   202110 EA   MATH 1240 RW_E

library(dplyr)

st01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L)
mc02_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L)
rw01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202080L)

test_that("ST01: HIST majors' registrations by teaching unit, late drops in, duplicates and non-members out", {
  res <- get_major_course_units(test_student_terms_st, test_students_st,
                                list(dept_code = "HIST", min_n = 1L, data_edges = st01_edges))

  expect_equal(names(res), c("term", "campus", "college", "dept_code", "is_own_unit", "in_progress",
                             "n_registrations", "n_students", "term_registrations", "term_students",
                             "share_of_registrations"))
  expect_equal(res$term, c(202010L, 202010L, 202010L, 202110L))
  expect_equal(res$dept_code, c("HIST", "ENGL", "MATH", "HIST"))
  expect_equal(res$is_own_unit, c(TRUE, FALSE, FALSE, TRUE))
  expect_false(any(res$in_progress))
  # ST_F's two HIST 1110 rows are one registration; ST_H's late-dropped MATH counts.
  expect_equal(res$n_registrations, c(8L, 1L, 1L, 1L))
  expect_equal(res$n_students, c(8L, 1L, 1L, 1L))
  expect_equal(res$term_registrations, c(10L, 10L, 10L, 1L))
  expect_equal(res$term_students, c(8L, 8L, 8L, 1L))
  expect_equal(res$share_of_registrations, c(0.8, 0.1, 0.1, 1))

  expect_equal(attr(res, "edge"), 202110L)
  expect_equal(attr(res, "latest_term"), 202110L)
  expect_equal(attr(res, "n_member_student_terms"), 9L)
  expect_equal(attr(res, "n_members"), 9L)
  expect_equal(attr(res, "n_unmapped"), 0L)
  expect_equal(nrow(attr(res, "suppressed")), 0L)
})

test_that("ST01: the course grain is the same registrations one level down, with the share of members", {
  res <- get_major_course_units(test_student_terms_st, test_students_st,
                                list(dept_code = "HIST", min_n = 1L, grain = "course", data_edges = st01_edges))
  expect_equal(names(res), c("term", "campus", "college", "dept_code", "subject_course", "is_own_unit",
                             "in_progress", "n_registrations", "n_students", "term_registrations",
                             "term_students", "share_of_registrations", "share_of_students"))
  expect_equal(res$term, c(202010L, 202010L, 202010L, 202110L))
  expect_equal(res$subject_course, c("HIST 1110", "ENGL 1110", "MATH 1215", "HIST 1110"))
  expect_equal(res$dept_code, c("HIST", "ENGL", "MATH", "HIST"))
  expect_equal(res$n_students, c(8L, 1L, 1L, 1L))
  # The totals are the term and campus's, as at the unit grain.
  expect_equal(res$term_students, c(8L, 8L, 8L, 1L))
  expect_equal(res$share_of_students, c(1, 0.125, 0.125, 1))

  sup <- attr(get_major_course_units(test_student_terms_st, test_students_st,
                                     list(dept_code = "HIST", min_n = 2L, grain = "course",
                                          data_edges = st01_edges)), "suppressed")
  expect_equal(sup$subject_course, c("ENGL 1110", "MATH 1215", "HIST 1110"))

  expect_error(get_major_course_units(test_student_terms_st, test_students_st,
                                      list(dept_code = "HIST", grain = "section", data_edges = st01_edges)),
               "grain")
})

test_that("MC02: two courses of one unit are two rows at the course grain, each with its own students", {
  res <- get_major_course_units(test_student_terms_mc, test_students_mc,
                                list(dept_code = "SPAN", min_n = 1L, grain = "course", data_edges = mc02_edges))
  first <- res %>% filter(term == 202010L)
  expect_equal(first$campus, c("ABQ", "ABQ", "GA"))
  expect_equal(first$subject_course, c("SPAN 101", "SPAN 101L", "SPAN 101"))
  expect_equal(first$n_students, c(4L, 2L, 2L))
  expect_equal(first$share_of_students, c(1, 0.5, 1))
})

test_that("member_programs lists the unit's programs before program_code narrows the members", {
  all_programs <- get_major_course_units(test_student_terms_st, test_students_st,
                                         list(dept_code = "HIST", min_n = 1L, data_edges = st01_edges))
  expect_equal(attr(all_programs, "member_programs"),
               tibble::tibble(primary_major_code = "HIST", is_pre_major = FALSE, n_students = 9L))
  # A program the unit does not hold leaves no member, and the list is unchanged.
  none <- get_major_course_units(test_student_terms_st, test_students_st,
                                 list(dept_code = "HIST", min_n = 1L, program_code = "SPAN",
                                      data_edges = st01_edges))
  expect_equal(nrow(none), 0L)
  expect_equal(attr(none, "n_members"), 0L)
  expect_equal(attr(none, "member_programs"), attr(all_programs, "member_programs"))
})

test_that("ST01: min_n suppresses unit rows and leaves the term totals alone", {
  res <- get_major_course_units(test_student_terms_st, test_students_st,
                                list(dept_code = "HIST", min_n = 2L, data_edges = st01_edges))
  expect_equal(nrow(res), 1L)
  expect_equal(res$dept_code, "HIST")
  expect_equal(res$term_registrations, 10L)
  expect_equal(res$share_of_registrations, 0.8)
  sup <- attr(res, "suppressed")
  expect_equal(sup$dept_code, c("ENGL", "MATH", "HIST"))
  expect_equal(sup$term, c(202010L, 202010L, 202110L))
  expect_equal(sup$n_students, c(1L, 1L, 1L))
})

test_that("ST01: a subject with no unit is its own NA row, counted, never dropped", {
  # The same class list with ENGL's subject undecided in subjects.csv.
  regs <- test_students_st %>%
    mutate(department = if_else(subject_course == "ENGL 1110", NA_character_, department))
  res <- get_major_course_units(test_student_terms_st, regs,
                                list(dept_code = "HIST", min_n = 1L, data_edges = st01_edges))
  expect_true(any(is.na(res$dept_code)))
  na_row <- res %>% filter(is.na(dept_code))
  expect_equal(na_row$n_registrations, 1L)
  expect_false(na_row$is_own_unit)
  expect_equal(attr(res, "n_unmapped"), 1L)
  expect_equal(res$term_registrations[res$term == 202010L], rep(10L, 3))
})

test_that("MC02: campus is beside the unit; a campus option scopes, never merges", {
  res <- get_major_course_units(test_student_terms_mc, test_students_mc,
                                list(dept_code = "SPAN", min_n = 1L, data_edges = mc02_edges))
  expect_equal(res$term,   c(202010L, 202010L, 202080L, 202080L, 202110L))
  expect_equal(res$campus, c("ABQ", "GA", "ABQ", "ABQ", "ABQ"))
  expect_equal(res$dept_code, c("SPAN", "SPAN", "SPAN", "PHIL", "SPAN"))
  expect_equal(res$n_registrations, c(6L, 2L, 4L, 1L, 1L))
  expect_equal(res$n_students,      c(4L, 2L, 4L, 1L, 1L))
  expect_equal(res$term_registrations, c(6L, 2L, 5L, 5L, 1L))
  expect_equal(res$share_of_registrations, c(1, 1, 0.8, 0.2, 1))

  ga <- get_major_course_units(test_student_terms_mc, test_students_mc,
                               list(dept_code = "SPAN", min_n = 1L, campus = "GA", data_edges = mc02_edges))
  expect_equal(nrow(ga), 1L)
  expect_equal(ga$campus, "GA")
  expect_equal(ga$n_students, 2L)
  # Scoping the campus does not change who is a member.
  expect_equal(attr(ga, "n_member_student_terms"), attr(res, "n_member_student_terms"))
})

test_that("RW01: rows stop at the settled edge; in-progress terms come in only when asked, labelled", {
  settled <- get_major_course_units(test_student_terms_rw, test_students_rw,
                                    list(dept_code = "SPAN", min_n = 1L, data_edges = rw01_edges))
  expect_equal(settled$term, 202080L)
  expect_equal(settled$dept_code, "ENGL")
  expect_false(settled$is_own_unit)
  expect_equal(attr(settled, "latest_term"), 202080L)

  current <- get_major_course_units(test_student_terms_rw, test_students_rw,
                                    list(dept_code = "SPAN", min_n = 1L, include_in_progress = TRUE,
                                         data_edges = rw01_edges))
  expect_equal(current$term,   c(202080L, 202110L, 202110L))
  expect_equal(current$campus, c("ABQ", "ABQ", "EA"))
  expect_equal(current$dept_code, c("ENGL", "HIST", "MATH"))
  expect_equal(current$n_students, c(1L, 3L, 1L))
  expect_equal(current$in_progress, c(FALSE, TRUE, TRUE))
  expect_equal(attr(current, "edge"), 202080L)
  expect_equal(attr(current, "latest_term"), 202110L)

  one_term <- get_major_course_units(test_student_terms_rw, test_students_rw,
                                     list(dept_code = "HIST", min_n = 1L, term = 202080L,
                                          data_edges = rw01_edges))
  expect_equal(one_term$dept_code, c("HIST", "ENGL"))
  expect_equal(one_term$n_students, c(5L, 3L))
  expect_equal(one_term$term_students, c(5L, 5L))
})

test_that("get_major_course_units() stops without a unit, an edge, or the attached columns", {
  expect_error(get_major_course_units(test_student_terms_st, test_students_st,
                                      list(data_edges = st01_edges)), "dept_code")
  expect_error(get_major_course_units(test_student_terms_st, test_students_st,
                                      list(dept_code = "HIST")), "last_enrolled_complete")
  expect_error(get_major_course_units(test_student_terms_st, test_students_st,
                                      list(dept_code = "HIST", include_in_progress = TRUE,
                                           data_edges = list(last_enrolled_complete = 202110L))),
               "last_enrolled")
  expect_error(get_major_course_units(test_student_terms_st %>% select(-primary_dept_code),
                                      test_students_st, list(dept_code = "HIST", data_edges = st01_edges)),
               "primary_dept_code")
  expect_error(get_major_course_units(test_student_terms_st, test_students_st %>% select(-department),
                                      list(dept_code = "HIST", data_edges = st01_edges)),
               "department")
})
