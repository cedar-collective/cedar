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

context("GPA Timeline")


# S1 — three terms, all graded, whole record inside the window.
# S2 — starts in the first term of the data, so left-truncated.
make_gpa_students <- function() {
  tibble::tibble(
    student_id = c(rep("S1", 4), rep("S2", 2)),
    term       = c(202080L, 202080L, 202110L, 202180L, 202010L, 202110L),
    final_grade = c("A", "B",  "C",  "A",  "B",  "A"),
    credits     = c(3,   3,    3,    3,    3,    3),
    subject_course = c("AAA 101", "BBB 101", "CCC 101", "DDD 101",
                       "EEE 101", "FFF 101")
  )
}


test_that("term GPA is credit-weighted within the term", {
  tl <- build_gpa_timeline(make_gpa_students())
  s1 <- dplyr::filter(tl, student_id == "S1") %>% dplyr::arrange(term)

  # 202080: A (4.0) and B (3.0), 3 credits each -> 3.5
  expect_equal(s1$term_gpa[s1$term == 202080L], 3.5)
  expect_equal(s1$graded_hours[s1$term == 202080L], 6)
})


test_that("gpa_after accumulates across terms", {
  tl <- build_gpa_timeline(make_gpa_students())
  s1 <- dplyr::filter(tl, student_id == "S1") %>% dplyr::arrange(term)

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
  tl <- build_gpa_timeline(make_gpa_students())
  s1 <- dplyr::filter(tl, student_id == "S1") %>% dplyr::arrange(term)

  expect_equal(s1$gpa_entering[s1$term == 202110L], 3.5)   # = gpa_after(202080)
  expect_equal(s1$gpa_entering[s1$term == 202180L], 3.0)   # = gpa_after(202110)
})


test_that("the first graded term has NA entering GPA, not zero", {
  # 0.0 would read as a failing student and would drag every group mean it lands
  # in; there is simply no prior record.
  tl <- build_gpa_timeline(make_gpa_students())
  s1 <- dplyr::filter(tl, student_id == "S1")
  expect_true(is.na(s1$gpa_entering[s1$term == 202080L]))
  expect_equal(s1$graded_hours_entering[s1$term == 202080L], 0)
})


test_that("non-point grades are excluded from both numerator and hours", {
  # W/CR/I carry no points. Counting their hours in the denominator only would
  # understate every affected student.
  st <- tibble::tibble(
    student_id  = rep("S9", 4),
    term        = 202080L,
    final_grade = c("A", "W", "CR", "I"),
    credits     = c(3, 3, 3, 3)
  )
  tl <- build_gpa_timeline(st)
  expect_equal(nrow(tl), 1)
  expect_equal(tl$term_gpa, 4.0)
  expect_equal(tl$graded_hours, 3)      # not 12
})


test_that("left-truncated students are marked invalid", {
  tl <- build_gpa_timeline(make_gpa_students())
  # 202010 is the first term in the data, so S2's earlier record is invisible.
  expect_false(unique(dplyr::filter(tl, student_id == "S2")$timeline_valid))
  expect_true(all(dplyr::filter(tl, student_id == "S1")$timeline_valid))
})


test_that("a student with no gradeable rows yields no timeline rows", {
  st <- tibble::tibble(
    student_id = "S8", term = 202080L, final_grade = "W", credits = 3
  )
  expect_equal(nrow(build_gpa_timeline(st)), 0)
})


test_that("missing required columns are an explicit error", {
  expect_error(
    build_gpa_timeline(tibble::tibble(student_id = "S1", term = 202080L)),
    "missing required column"
  )
})


# ── attach_gpa_position ──────────────────────────────────────────────────────

test_that("attach_gpa_position takes the most recent graded term at or before the event", {
  tl <- build_gpa_timeline(make_gpa_students())
  events <- tibble::tibble(student_id = "S1", covariate_term = 202180L)
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")

  expect_equal(nrow(out), 1)
  expect_equal(out$gpa_entering, 3.0)   # entering 202180
})


test_that("attach_gpa_position places an event in an ungraded term from the prior record", {
  # A term with only withdrawals produces no timeline row. The student still has
  # a record walking into it, and a plain (student_id, term) join would drop them.
  tl <- build_gpa_timeline(make_gpa_students())
  events <- tibble::tibble(student_id = "S1", covariate_term = 202160L)
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")

  expect_equal(nrow(out), 1)
  expect_equal(out$gpa_entering, 3.5)   # carried from 202110's entering value
})


test_that("attach_gpa_position yields NA before a student's first graded term", {
  tl <- build_gpa_timeline(make_gpa_students())
  events <- tibble::tibble(student_id = "S1", covariate_term = 201980L)
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")

  expect_equal(nrow(out), 1)
  expect_true(is.na(out$gpa_entering))
})


test_that("attach_gpa_position never duplicates or drops event rows", {
  tl <- build_gpa_timeline(make_gpa_students())
  events <- tibble::tibble(
    student_id     = c("S1", "S1", "S2", "ghost"),
    covariate_term = c(202080L, 202180L, 202110L, 202110L)
  )
  out <- attach_gpa_position(events, tl, term_col = "covariate_term")
  expect_equal(nrow(out), nrow(events))
})


test_that("an empty timeline yields NA columns rather than an error", {
  events <- tibble::tibble(student_id = "S1", covariate_term = 202080L)
  out <- attach_gpa_position(events, build_gpa_timeline(
    tibble::tibble(student_id = character(), term = integer(),
                   final_grade = character(), credits = numeric())),
    term_col = "covariate_term")
  expect_true(is.na(out$gpa_entering))
  expect_false(out$timeline_valid)
})
