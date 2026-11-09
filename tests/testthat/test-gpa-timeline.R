# Tests for build_gpa_timeline() and attach_gpa_position() — R/branches/gpa-timeline.R
#
# The point of this branch is that `inst_gpa` on cedar_programs is stamped as of
# the data pull and repeats a student's final GPA on every historical row, so it
# cannot be matched on. These tests pin the arithmetic of the replacement and,
# more importantly, the two properties that make it safe to match on:
#
#   * gpa_entering excludes the term's own grades (in a course-effect study those
#     grades are the outcome), and
#   * left-truncated students are marked, because a running mean over a record
#     that starts mid-career is not a cumulative GPA.
#
# Since ADR-001 step 7 group 4 the series is read off cedar_student_terms, whose
# grade-point columns the transform sums (build_student_terms()); the tests
# build that table over a designed class list, as the transform does.

context("GPA Timeline")


# GP_S1 — three terms, all graded, whole record inside the window.
# GP_S2 — starts in the first term of the data, so left-truncated.
# GP_S9 — one term with an A beside W, CR and I: points for the A only.
# GP_S8 — a W only: no graded hours, no timeline row.
# Rows through the ST01 constructor (3 credits each, registered, ABQ).
make_gpa_students <- function() {
  dplyr::bind_rows(
    .st_row("GP_S1", 202080L, "AAA 101", "RE", "A"),
    .st_row("GP_S1", 202080L, "BBB 101", "RE", "B"),
    .st_row("GP_S1", 202110L, "CCC 101", "RE", "C"),
    .st_row("GP_S1", 202180L, "DDD 101", "RE", "A"),
    .st_row("GP_S2", 202010L, "EEE 101", "RE", "B"),
    .st_row("GP_S2", 202110L, "FFF 101", "RE", "A"),
    .st_row("GP_S9", 202080L, "GGG 101", "RE", "A"),
    .st_row("GP_S9", 202080L, "HHH 101", "RE", "W"),
    .st_row("GP_S9", 202080L, "III 101", "RE", "CR"),
    .st_row("GP_S9", 202080L, "JJJ 101", "RE", "I"),
    .st_row("GP_S8", 202080L, "KKK 101", "RE", "W")
  )
}

gpa_student_terms <- function(students = make_gpa_students()) {
  suppressMessages(build_student_terms(
    students, programs = NULL, degrees = NULL,
    edges = list(last_enrolled_complete = 202180L)
  ))
}

gpa_timeline <- function() build_gpa_timeline(gpa_student_terms())


test_that("the student-term table carries the grade points the series divides", {
  st <- gpa_student_terms()
  s1 <- dplyr::filter(st, student_id == "GP_S1") %>% dplyr::arrange(term)
  # 202080: A (4.0) and B (3.0), 3 credits each -> 21 points over 6 hours
  expect_equal(s1$quality_points, c(21, 6, 12))
  expect_equal(s1$graded_hours, c(6, 3, 3))
  expect_equal(s1$cumulative_quality_points, c(21, 27, 39))
  expect_equal(s1$cumulative_graded_hours, c(6, 9, 12))
  # W, CR and I carry no points and no hours; the credits were still attempted.
  s9 <- dplyr::filter(st, student_id == "GP_S9")
  expect_equal(s9$quality_points, 12)
  expect_equal(s9$graded_hours, 3)
  expect_equal(s9$attempted_unm_credits, 12)
  s8 <- dplyr::filter(st, student_id == "GP_S8")
  expect_equal(s8$graded_hours, 0)
})


test_that("term GPA is credit-weighted within the term", {
  tl <- gpa_timeline()
  s1 <- dplyr::filter(tl, student_id == "GP_S1") %>% dplyr::arrange(term)

  # 202080: A (4.0) and B (3.0), 3 credits each -> 3.5
  expect_equal(s1$term_gpa[s1$term == 202080L], 3.5)
  expect_equal(s1$graded_hours[s1$term == 202080L], 6)
})


test_that("gpa_after accumulates across terms", {
  tl <- gpa_timeline()
  s1 <- dplyr::filter(tl, student_id == "GP_S1") %>% dplyr::arrange(term)

  # Through 202080: (4+3)*3 = 21 points / 6 hours = 3.5
  expect_equal(s1$gpa_after[s1$term == 202080L], 3.5)
  # Through 202110: 21 + 2.0*3 = 27 / 9 = 3.0
  expect_equal(s1$gpa_after[s1$term == 202110L], 3.0)
  # Through 202180: 27 + 4.0*3 = 39 / 12 = 3.25
  expect_equal(s1$gpa_after[s1$term == 202180L], 3.25)
})


test_that("gpa_entering excludes the term's own grades", {
  # This is the property that makes the covariate usable in a course-effect
  # study: the term being compared contributes the outcome, so it must not also
  # contribute the covariate.
  tl <- gpa_timeline()
  s1 <- dplyr::filter(tl, student_id == "GP_S1") %>% dplyr::arrange(term)

  expect_equal(s1$gpa_entering[s1$term == 202110L], 3.5)   # = gpa_after(202080)
  expect_equal(s1$gpa_entering[s1$term == 202180L], 3.0)   # = gpa_after(202110)
})


test_that("the first graded term has NA entering GPA, not zero", {
  # 0.0 would read as a failing student and would drag every group mean it lands
  # in; there is simply no prior record.
  tl <- gpa_timeline()
  s1 <- dplyr::filter(tl, student_id == "GP_S1")
  expect_true(is.na(s1$gpa_entering[s1$term == 202080L]))
  expect_equal(s1$graded_hours_entering[s1$term == 202080L], 0)
})


test_that("non-point grades are excluded from both numerator and hours", {
  # W/CR/I carry no points. Counting their hours in the denominator only would
  # understate every affected student.
  tl <- dplyr::filter(gpa_timeline(), student_id == "GP_S9")
  expect_equal(nrow(tl), 1)
  expect_equal(tl$term_gpa, 4.0)
  expect_equal(tl$graded_hours, 3)      # not 12
})


test_that("left-truncated students are marked invalid, by the table's flag", {
  tl <- gpa_timeline()
  # 202010 is the first term in the data, so GP_S2's earlier record is invisible.
  expect_false(unique(dplyr::filter(tl, student_id == "GP_S2")$timeline_valid))
  expect_true(all(dplyr::filter(tl, student_id == "GP_S1")$timeline_valid))
  # The flag is the table's, over the whole data: a slice of the table keeps it.
  sliced <- build_gpa_timeline(dplyr::filter(gpa_student_terms(), student_id == "GP_S2"))
  expect_false(unique(sliced$timeline_valid))
})


test_that("a student with no gradeable rows yields no timeline rows", {
  tl <- gpa_timeline()
  expect_false("GP_S8" %in% tl$student_id)
  expect_equal(nrow(build_gpa_timeline(gpa_student_terms(), opt = list(student_ids = "GP_S8"))), 0)
})


test_that("missing columns and the class list's window options are explicit errors", {
  expect_error(
    build_gpa_timeline(tibble::tibble(student_id = "S1", term = 202080L)),
    "missing required column"
  )
  # The class list itself is not the table.
  expect_error(build_gpa_timeline(make_gpa_students()), "missing required column")
  expect_error(
    build_gpa_timeline(gpa_student_terms(), opt = list(min_data_term = 202010L)),
    "not an option it answers"
  )
})


# ── attach_gpa_position ──────────────────────────────────────────────────────

test_that("attach_gpa_position takes the most recent graded term at or before the event", {
  tl <- gpa_timeline()
  events <- tibble::tibble(student_id = "GP_S1", covariate_term = 202180L)
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")

  expect_equal(nrow(out), 1)
  expect_equal(out$gpa_entering, 3.0)   # entering 202180
})


test_that("attach_gpa_position places an event in an ungraded term from the prior record", {
  # A term with only withdrawals produces no timeline row. The student still has
  # a record walking into it, and a plain (student_id, term) join would drop them.
  tl <- gpa_timeline()
  events <- tibble::tibble(student_id = "GP_S1", covariate_term = 202160L)
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")

  expect_equal(nrow(out), 1)
  expect_equal(out$gpa_entering, 3.5)   # carried from 202110's entering value
})


test_that("attach_gpa_position yields NA before a student's first graded term", {
  tl <- gpa_timeline()
  events <- tibble::tibble(student_id = "GP_S1", covariate_term = 201980L)
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")

  expect_equal(nrow(out), 1)
  expect_true(is.na(out$gpa_entering))
})


test_that("attach_gpa_position never duplicates or drops event rows", {
  tl <- gpa_timeline()
  events <- tibble::tibble(
    student_id     = c("GP_S1", "GP_S1", "GP_S2", "ghost"),
    covariate_term = c(202080L, 202180L, 202110L, 202110L)
  )
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")
  expect_equal(nrow(out), nrow(events))
})


test_that("an empty timeline yields NA columns rather than an error", {
  events <- tibble::tibble(student_id = "GP_S1", covariate_term = 202080L)
  out <- attach_gpa_position(
    events,
    build_gpa_timeline(gpa_student_terms(), opt = list(student_ids = "GP_S8")),
    term_col = "covariate_term"
  )
  expect_true(is.na(out$gpa_entering))
  expect_false(out$timeline_valid)
})
