# Tests for R/branches/student-terms.R — one row per student-term
#
# Contract: docs/developers/student-terms.md. Fixture: ST01, eleven students,
# each guarding one rule. Mutation checks recorded 2026-11-03 — each of these
# breaks the named assertion when reintroduced:
#   enrolled = registered only                -> ST_A enrolled/returned (I44)
#   a DW counted as a DFW grade               -> ST_H dfw_grades
#   every Major row as primary                -> ST_G primary_major_code
#   class list winning precedence             -> ST_F classification
#   Summer as a return term                   -> ST_D returned
#   returned FALSE past the settled edge      -> ST_I returned NA
#   a return judged into a term with no pull  -> gap test, ST_A return_observable

context("Student terms")

st01 <- function() build_student_terms(test_students_st, test_programs_st, test_degrees_st)
row <- function(st, sid, term) {
  r <- st[st$student_id == sid & st$term == term, ]
  if (nrow(r) != 1L) stop("expected one row for ", sid, " ", term, ", got ", nrow(r))
  r
}


test_that("one row per student-term with any class-list row or declaration, pinned", {
  st <- st01()
  expect_equal(nrow(st), 17L)
  expect_equal(sum(st$enrolled), 14L)
  expect_equal(sum(st$declared & st$class_list_rows == 0L), 1L)
  expect_equal(sum(st$description_conflict), 1L)
  expect_equal(sum(st$degree_awarded), 1L)
  expect_equal(names(st), STUDENT_TERMS_COLUMNS)
  expect_false(any(STUDENT_TERMS_BANNED_COLUMNS %in% names(st)))
})

test_that("ST_A: a late withdrawal next term is enrolled, so the student returned (I44)", {
  st <- st01()
  a80 <- row(st, "ST_A", 202080L)
  expect_true(a80$enrolled)
  expect_equal(a80$class_list_rows, 1L)
  expect_equal(a80$registered_courses, 0L)
  expect_equal(a80$late_withdrawals, 1L)
  a10 <- row(st, "ST_A", 202010L)
  expect_equal(a10$next_regular_term, 202080L)
  expect_true(a10$return_observable)
  expect_true(a10$returned_next_regular_term)
})

test_that("ST_B and ST_C: an early drop or a waitlist next term is a row, not enrollment", {
  st <- st01()
  b80 <- row(st, "ST_B", 202080L)
  expect_false(b80$enrolled)
  expect_equal(b80$class_list_rows, 1L)
  expect_equal(b80$early_drops, 1L)
  expect_false(row(st, "ST_B", 202010L)$returned_next_regular_term)
  c80 <- row(st, "ST_C", 202080L)
  expect_false(c80$enrolled)
  expect_true(c80$waitlisted_only)
  expect_false(row(st, "ST_C", 202010L)$returned_next_regular_term)
  expect_false(row(st, "ST_A", 202080L)$waitlisted_only)
})

test_that("ST_D: Summer is not a return term", {
  st <- st01()
  d10 <- row(st, "ST_D", 202010L)
  expect_equal(d10$next_regular_term, 202080L)
  expect_false(d10$returned_next_regular_term)
  d60 <- row(st, "ST_D", 202060L)
  expect_true(d60$enrolled)
  expect_equal(d60$next_regular_term, 202080L)
  expect_false(d60$returned_next_regular_term)
})

test_that("ST_E: a declaration with no class list is a row with enrolled FALSE", {
  st <- st01()
  e80 <- row(st, "ST_E", 202080L)
  expect_true(e80$declared)
  expect_false(e80$enrolled)
  expect_equal(e80$class_list_rows, 0L)
  expect_equal(e80$description_source, "programs")
  expect_true(is.na(e80$classlist_as_of))
  expect_equal(e80$primary_major_code, "HIST")
  expect_false(row(st, "ST_E", 202010L)$returned_next_regular_term)
})

test_that("ST_F: the newest class-list pull is read, programs wins, and the conflict is flagged", {
  st <- st01()
  f <- row(st, "ST_F", 202010L)
  expect_equal(f$student_classification, "Sophomore, 2nd Yr")
  expect_equal(f$description_source, "programs")
  expect_true(f$description_conflict)
  expect_equal(f$classlist_as_of, as.Date("2021-02-15"))
  # a student whose two sources agree is both_agree, not a conflict
  a <- row(st, "ST_A", 202010L)
  expect_equal(a$description_source, "both_agree")
  expect_false(a$description_conflict)
})

test_that("ST_G: the primary major is the first Major row by code, and every declaration is counted", {
  st <- st01()
  g <- row(st, "ST_G", 202010L)
  expect_equal(g$primary_major_code, "AA")
  expect_equal(g$primary_dept_code, "AA")
  expect_equal(g$n_declarations, 3L)
  expect_true(g$declared)
  expect_false(g$is_pre_major)
})

test_that("ST_H: late drops are withdrawals, never DFW grades; credits follow the registered rows", {
  st <- st01()
  h <- row(st, "ST_H", 202010L)
  expect_equal(h$class_list_rows, 3L)
  expect_equal(h$registered_courses, 2L)
  expect_equal(h$late_withdrawals, 1L)
  expect_equal(h$dfw_grades, 1L)      # the C-
  expect_equal(h$graded_rows, 2L)
  expect_equal(h$attempted_unm_credits, 6)
  expect_equal(h$completed_unm_credits, 3)   # A earns credit under passing_grades; C- does not
})

test_that("ST_I: a return past the settled edge is NA, never FALSE", {
  st <- st01()
  i <- row(st, "ST_I", 202110L)
  expect_equal(i$next_regular_term, 202180L)
  expect_false(i$return_observable)
  expect_true(is.na(i$returned_next_regular_term))
  expect_true(all(!is.na(st$returned_next_regular_term[st$return_observable])))
})

test_that("a Fall or Spring with no class list makes the return into it unobservable, never FALSE", {
  # Drop every Fall 2020 class-list row: Spring 2020 and Spring 2021 remain,
  # the settled edge still reaches Spring 2021, and Fall 2020 is a gap. Before
  # this rule, every Spring 2020 student read as not returning.
  expect_message(
    st <- build_student_terms(dplyr::filter(test_students_st, term != 202080L),
                              test_programs_st, test_degrees_st),
    "no class list for Fall 2020")
  a <- row(st, "ST_A", 202010L)
  expect_equal(a$next_regular_term, 202080L)
  expect_false(a$return_observable)
  expect_true(is.na(a$returned_next_regular_term))
  # Summer 2020's next regular term is the same gap.
  expect_false(row(st, "ST_D", 202060L)$return_observable)
  expect_false(any(st$return_observable[st$next_regular_term == 202080L]))
  # The complete fixture judges Spring 2020 returns, as ST_A shows.
  expect_true(row(st01(), "ST_A", 202010L)$return_observable)
})

test_that("ST_J: a degree awarded sits beside the return flag; the table does not combine them", {
  st <- st01()
  j <- row(st, "ST_J", 202010L)
  expect_true(j$degree_awarded)
  expect_false(j$returned_next_regular_term)
  expect_equal(sum(st$degree_awarded), 1L)
})

test_that("ST_K: with no programs row the class list describes the student, in code vocabulary", {
  st <- st01()
  k <- row(st, "ST_K", 202010L)
  expect_equal(k$description_source, "class_list")
  expect_false(k$declared)
  expect_equal(k$n_declarations, 0L)
  expect_true(is.na(k$primary_major_code))
  expect_true(is.na(k$academic_standing))
  expect_equal(k$student_level, "UG")
  expect_equal(k$student_campus, "ABQ")
  # the programs names resolve to the same codes through the institution's files
  a <- row(st, "ST_A", 202010L)
  expect_equal(a$student_level, "UG")
  expect_equal(a$student_campus, "ABQ")
  expect_equal(a$academic_standing, "Good Standing")
  expect_equal(a$sem_gpa, 3.5)
  expect_true(row(st, "ST_K", 202080L)$returned_next_regular_term == FALSE |
                is.na(row(st, "ST_K", 202080L)$returned_next_regular_term))
})

test_that("credit position is a running total over the student's terms", {
  st <- st01()
  k10 <- row(st, "ST_K", 202010L); k80 <- row(st, "ST_K", 202080L)
  expect_equal(k10$unm_credits_entering, 0)
  expect_equal(k10$cumulative_attempted_unm_credits, 3)
  expect_equal(k80$unm_credits_entering, 3)
  expect_equal(k80$cumulative_attempted_unm_credits, 6)
  # every ST01 student first appears in the data's first term, so none is valid
  expect_false(any(st$timeline_valid[st$student_id != "ST_I"]))
  expect_true(row(st, "ST_I", 202110L)$timeline_valid)
})

test_that("the build fails loudly without a settled edge or with a missing column", {
  e <- cedar_data_edges(test_students_st, degrees = test_degrees_st)
  e$last_enrolled_complete <- NULL
  expect_error(build_student_terms(test_students_st, test_programs_st, test_degrees_st, edges = e),
               "settled edge")
  expect_error(build_student_terms(dplyr::select(test_students_st, -residency), test_programs_st),
               "residency")
})

test_that("two values in one pull is an error, not a choice", {
  twice <- dplyr::bind_rows(
    test_students_st,
    dplyr::mutate(dplyr::filter(test_students_st, student_id == "ST_A", term == 202010L),
                  enrollment_id = paste0(enrollment_id, "-x"), student_classification = "Junior, 3rd Yr"))
  expect_error(build_student_terms(twice, test_programs_st, test_degrees_st), "more than one")
})

test_that("the validator rejects a banned column, a repeated key and a misjudged return", {
  st <- st01()
  expect_error(validate_student_terms(dplyr::mutate(st, inst_gpa = 3)), "pull-stamped")
  expect_error(validate_student_terms(dplyr::bind_rows(st, st[1, ])), "repeats")
  broken <- st
  broken$returned_next_regular_term[!broken$return_observable] <- FALSE
  expect_error(validate_student_terms(broken), "return_observable")
  nested <- st
  nested$student_level <- st[, c("student_level", "student_campus")]
  expect_error(validate_student_terms(nested), "plain vectors")
})

test_that("attach_student_term() joins named columns and refuses a clash", {
  st <- st01()
  rows <- dplyr::distinct(test_students_st, student_id, term, registration_status_code)
  out <- attach_student_term(rows, st, c("enrolled", "primary_major_code"))
  expect_equal(nrow(out), nrow(rows))
  expect_true(all(c("enrolled", "primary_major_code") %in% names(out)))
  expect_error(attach_student_term(out, st, "enrolled"), "already carry")
  expect_error(attach_student_term(rows, st, "nope"), "not on the student-term table")
})
