# Tests for R/branches/credit-timeline.R
#
# The branch exists because the cumulative credit columns on cedar_programs are
# a snapshot of the pull date replicated onto every historical row. Read the
# field reliability contract in AGENTS.md, then the CT01 block in
# fixtures/designed_test_data.R — every number below is stated there.

source(file.path(dirname(getwd()), "testthat", "fixtures", "designed_test_data.R"))

context("Per-Term Credit Position")


test_that("timeline gives credits entering the term, not after it", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  a <- dplyr::filter(tl, student_id == "CT_A") %>% dplyr::arrange(term)

  # Transfer block 30, then 12 credits a term. Entering the first term the
  # student has only their transfer credit — the term's own load must not be
  # counted toward the position it is being placed at.
  expect_equal(a$total_credits_entering, c(30, 42, 54, 66))
  expect_equal(a$total_credits_after,    c(42, 54, 66, 78))
})

test_that("the transfer block is recovered from the frozen pair", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  # overall(78) - inst(48) = 30. Both columns are frozen, but their difference
  # is taken at one instant and so survives the freeze.
  expect_equal(unique(tl$transfer_credits[tl$student_id == "CT_A"]), 30)
  expect_equal(unique(tl$transfer_credits[tl$student_id == "CT_B"]), 30)
})

test_that("students with no program record get a UNM-only timeline, not an error", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  c3 <- dplyr::filter(tl, student_id == "CT_C")

  expect_equal(unique(c3$transfer_credits), 0)
  expect_equal(c3$total_credits_entering, c3$unm_credits_entering)
})

test_that("programs = NULL yields an honest UNM-only timeline", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, programs = NULL)
  expect_true(all(tl$transfer_credits == 0))
  expect_equal(tl$total_credits_entering, tl$unm_credits_entering)
})

test_that("timeline_valid marks students whose history predates the data", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)

  # CT_B's first term IS the first term in the data, so their running total
  # starts mid-career at zero and every position is understated.
  expect_false(unique(tl$timeline_valid[tl$student_id == "CT_B"]))
  expect_true(all(tl$timeline_valid[tl$student_id == "CT_A"]))
})

test_that("a term-filtered slice without first terms fails OPEN, which is why the override exists", {
  # Documents the trap rather than hiding it. Slicing away CT_B's 202010 row
  # makes their history look like it starts at 202080, and the guard cannot tell.
  slice <- dplyr::filter(cedar_student_term_credits_ct, term >= 202080L)
  naive <- build_credit_timeline(slice, cedar_programs_ct,
                                 opt = list(min_data_term = 202010L))
  expect_true(any(naive$timeline_valid[naive$student_id == "CT_B"]))
})

test_that("student_first_terms makes the guard immune to how the input was sliced", {
  slice <- dplyr::filter(cedar_student_term_credits_ct, term >= 202080L)
  firsts <- cedar_student_term_credits_ct %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(first_unm_term = min(term), .groups = "drop")
  tl <- build_credit_timeline(slice, cedar_programs_ct,
                              opt = list(min_data_term = 202010L,
                                         student_first_terms = firsts))

  expect_true(all(tl$timeline_valid[tl$student_id == "CT_A"]))
  expect_false(any(tl$timeline_valid[tl$student_id == "CT_B"]))
})

test_that("a student missing from student_first_terms is marked invalid, not valid", {
  firsts <- tibble::tibble(student_id = "CT_A", first_unm_term = 202080L)
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct,
                              opt = list(min_data_term = 202010L,
                                         student_first_terms = firsts))
  expect_true(all(tl$timeline_valid[tl$student_id == "CT_A"]))
  expect_false(any(tl$timeline_valid[tl$student_id == "CT_B"]))
  expect_false(any(tl$timeline_valid[tl$student_id == "CT_C"]))
})

test_that("a malformed student_first_terms fails loudly", {
  expect_error(
    build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct,
                          opt = list(student_first_terms = tibble::tibble(student_id = "CT_A"))),
    "student_id and first_unm_term"
  )
})

test_that("the position actually moves across a student's terms", {
  # The single property the frozen columns fail: within one student, the value
  # must change from term to term or it is not a timeline.
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  moved <- tl %>% dplyr::group_by(student_id) %>%
    dplyr::summarize(n_vals = dplyr::n_distinct(total_credits_entering),
                     n_terms = dplyr::n(), .groups = "drop") %>%
    dplyr::filter(n_terms > 1)
  expect_true(all(moved$n_vals == moved$n_terms))
})

test_that("student_ids restricts the timeline", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct,
                              opt = list(student_ids = "CT_A"))
  expect_equal(unique(tl$student_id), "CT_A")
})

test_that("an empty student filter returns a typed empty frame", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct,
                              opt = list(student_ids = "NOBODY"))
  expect_equal(nrow(tl), 0)
  expect_true(is.character(tl$student_id))
  expect_true(is.numeric(tl$total_credits_entering))
})

test_that("a malformed term_credits table fails loudly", {
  expect_error(
    build_credit_timeline(dplyr::select(cedar_student_term_credits_ct,
                                        -cumulative_attempted_unm_credits)),
    "missing required column"
  )
})

test_that("a programs table without the credit pair fails loudly", {
  expect_error(
    build_credit_timeline(cedar_student_term_credits_ct,
                          dplyr::select(cedar_programs_ct, student_id, term)),
    "to recover transfer credit"
  )
})


# =============================================================================
# attach_credit_position()
# =============================================================================

test_that("attach_credit_position joins the entering position onto events", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  events <- tibble::tibble(student_id = c("CT_A", "CT_A"),
                           change_term = c(202110L, 202210L))
  out <- attach_credit_position(events, tl, term_col = "change_term")

  expect_equal(out$credits_entering, c(42, 66))
  expect_true(all(out$timeline_valid))
})

test_that("attach_credit_position can use the UNM-only basis", {
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  events <- tibble::tibble(student_id = "CT_A", term = 202110L)
  out <- attach_credit_position(events, tl, basis = "unm")

  expect_equal(out$credits_entering, 12)   # 42 total minus the 30 transfer block
})

test_that("an event in a term with no graded enrollment keeps the row with NA", {
  # Dropping it would silently shrink the event count; the change still happened.
  tl <- build_credit_timeline(cedar_student_term_credits_ct, cedar_programs_ct)
  events <- tibble::tibble(student_id = "CT_A", term = 202480L)
  out <- attach_credit_position(events, tl)

  expect_equal(nrow(out), 1)
  expect_true(is.na(out$credits_entering))
})


# =============================================================================
# get_course_timing() credit axes now route through the timeline
# =============================================================================
#
# Regression guard for the migration: inst_credit_band and overall_credit_band
# used to read cedar_programs' frozen cumulative columns directly. If either
# ever falls back to them the position stops moving across a student's terms,
# which is precisely what these assert against.

ct_population <- function() {
  tibble::tibble(student_id = c("CT_A", "CT_C"), population_label = "ct")
}

ct_students <- function() {
  # CT_A takes one course per term across their four terms.
  tibble::tibble(
    student_id = rep("CT_A", 4),
    term = c(202080L, 202110L, 202180L, 202210L),
    subject_course = "CTMP 101",
    course_title = "Test Course",
    student_classification = "Freshman",
    registration_status_code = "RE",
    campus = "ABQ"
  )
}

test_that("inst_credit_band places a course by UNM credits entering the term", {
  timing <- suppressMessages(get_course_timing(
    ct_students(), ct_population(),
    opt = list(x_axis = "inst_credit_band", min_n = 1L, campus = "ABQ",
               group_campus = FALSE),
    term_credits = cedar_student_term_credits_ct
  ))
  # UNM entering: 0, 12, 24, 36 -> all band 1 (0-30) except the last (31-60).
  expect_setequal(timing$relative_term, c(1L, 2L))
})

test_that("overall_credit_band adds the transfer block and shifts the bands", {
  timing <- suppressMessages(get_course_timing(
    ct_students(), ct_population(), programs = cedar_programs_ct,
    opt = list(x_axis = "overall_credit_band", min_n = 1L, campus = "ABQ",
               group_campus = FALSE),
    term_credits = cedar_student_term_credits_ct
  ))
  # Total entering: 30, 42, 54, 66 -> bands 1, 2, 2, 3. The same student sits a
  # band higher than on the UNM axis, which is the whole point of the transfer
  # block; a frozen source would have put every term in one band.
  expect_setequal(timing$relative_term, c(1L, 2L, 3L))
})

test_that("credit axes refuse to run without term_credits", {
  expect_error(
    suppressMessages(get_course_timing(
      ct_students(), ct_population(), programs = cedar_programs_ct,
      opt = list(x_axis = "inst_credit_band", min_n = 1L, campus = "ABQ"))),
    "require cedar_student_term_credits"
  )
})

test_that("overall_credit_band refuses to run without programs", {
  # Without programs there is no transfer block, and silently returning the
  # UNM-only axis under the transfer-inclusive name would be the wrong number
  # under the right label.
  expect_error(
    suppressMessages(get_course_timing(
      ct_students(), ct_population(),
      opt = list(x_axis = "overall_credit_band", min_n = 1L, campus = "ABQ"),
      term_credits = cedar_student_term_credits_ct)),
    "recover the transfer block"
  )
})

test_that("the credit position moves across a student's terms on both axes", {
  # The single property the frozen columns failed.
  for (ax in c("inst_credit_band", "overall_credit_band")) {
    timing <- suppressMessages(get_course_timing(
      ct_students(), ct_population(), programs = cedar_programs_ct,
      opt = list(x_axis = ax, min_n = 1L, campus = "ABQ", group_campus = FALSE),
      term_credits = cedar_student_term_credits_ct))
    expect_gt(dplyr::n_distinct(timing$relative_term), 1)
  }
})
