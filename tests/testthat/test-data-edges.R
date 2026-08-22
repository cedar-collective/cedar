# Tests for R/branches/data-edges.R
#
# CEDAR's local data runs behind the registrar and a term arrives in stages:
# registration months early, grades weeks late. So the last ENROLLED term and
# the last GRADEABLE term are routinely different, and bounding a grade-based
# rate by the enrollment edge yields a confident wrong number rather than an
# error. Measured before this existed: the newest term's DFW rate read 0.3%
# against 6-8% for every other term.

context("Data Edges")


edge_students <- function() {
  mk <- function(term, n, graded) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded))
  )
  dplyr::bind_rows(
    mk(202480, 100, 91),   # finished, graded
    mk(202580, 100, 91),   # finished, graded
    mk(202610, 100, 7),    # finished, grades still landing
    mk(202660, 100, 0),    # registration only
    mk(202680, 100, 0)     # registration only, partial
  )
}

edge_degrees <- function() tibble::tibble(
  term = c(202480L, 202580L, 202610L),
  graduation_status = c("Awarded", "Awarded", "Pending")
)


test_that("the enrollment and graded edges are different terms", {
  # The whole reason this file exists. If these ever collapse to one number the
  # distinction has been lost and grade rates will silently reach into an
  # ungraded term again.
  e <- cedar_data_edges(edge_students())

  expect_equal(e$last_enrolled, 202680L)
  expect_equal(e$last_graded,   202580L)
  expect_lt(e$last_graded, e$last_enrolled)
})

test_that("a term with a trickle of early grades is not gradeable", {
  # 7% posted is enough to look non-empty and nowhere near enough to measure a
  # rate against.
  e <- cedar_data_edges(edge_students())
  expect_true(e$last_graded < 202610L)
})

test_that("the graded edge advances on its own once grades land", {
  later <- dplyr::bind_rows(
    dplyr::filter(edge_students(), term != 202610L),
    tibble::tibble(term = rep(202610L, 100),
                   final_grade = c(rep("A", 88), rep(NA_character_, 12)))
  )
  expect_equal(cedar_data_edges(later)$last_graded, 202610L)
})

test_that("the threshold is not finely balanced", {
  # Finished terms sit at 83-91% and in-flight at 0-7%, so any sane threshold
  # picks the same edge. A test that only passed at one exact value would mean
  # the separation was fragile.
  for (thr in c(0.2, 0.4, 0.5, 0.6, 0.8)) {
    expect_equal(cedar_data_edges(edge_students(), min_graded_share = thr)$last_graded,
                 202580L, info = paste("threshold", thr))
  }
})

test_that("first_enrolled comes from the data, not a hardcoded floor", {
  e <- cedar_data_edges(edge_students())
  expect_equal(e$first_enrolled, 202480L)
})

test_that("max_term caps every edge without changing the grade rule", {
  e <- cedar_data_edges(edge_students(), max_term = 202510L)
  expect_equal(e$last_enrolled, 202480L)
  expect_equal(e$last_graded,   202480L)
})

test_that("the degree edge counts awarded degrees only", {
  e <- cedar_data_edges(edge_students(), degrees = edge_degrees())
  # 202610 is Pending, so the edge is the last AWARDED term.
  expect_equal(e$last_degree, 202580L)
})

test_that("no degrees supplied yields NULL, not a guess", {
  expect_null(cedar_data_edges(edge_students())$last_degree)
})

test_that("an entirely ungraded snapshot reports NULL rather than nominating a term", {
  # Failing closed matters here: nominating an ungraded term would make every
  # student in it read as having no outcome.
  ungraded <- tibble::tibble(term = rep(202680L, 50), final_grade = NA_character_)
  e <- cedar_data_edges(ungraded)
  expect_null(e$last_graded)
  expect_equal(e$last_enrolled, 202680L)
})

test_that("graded_by_term shows the work behind the edge", {
  e <- cedar_data_edges(edge_students())
  expect_true(all(c("term", "rows", "graded_share") %in% names(e$graded_by_term)))
  expect_equal(nrow(e$graded_by_term), 5)
  expect_true(all(e$graded_by_term$graded_share >= 0 & e$graded_by_term$graded_share <= 1))
})

test_that("missing columns and empty input fail loudly", {
  expect_error(cedar_data_edges(tibble::tibble(term = 202480L)), "missing required column")
  expect_error(cedar_data_edges(edge_students()[0, ]), "non-empty students table")
})


# =============================================================================
# cedar_edge_note() — surfaces must say which edge they used
# =============================================================================

test_that("the graded note names the term and says why the next one is absent", {
  note <- cedar_edge_note(cedar_data_edges(edge_students()), "graded")
  expect_match(note, "Fall 2025")
  expect_match(note, "grades posted")
  expect_match(note, "Spring 2026")     # enrolled but not graded
})

test_that("the enrolled note names the enrollment edge", {
  note <- cedar_edge_note(cedar_data_edges(edge_students()), "enrolled")
  expect_match(note, "Fall 2026")
  expect_false(grepl("grades posted", note))
})

test_that("an unavailable edge yields NULL rather than a misleading sentence", {
  ungraded <- tibble::tibble(term = rep(202680L, 50), final_grade = NA_character_)
  expect_null(cedar_edge_note(cedar_data_edges(ungraded), "graded"))
})


# =============================================================================
# The settled-enrollment edge
# =============================================================================
#
# What cedar_report_end_term was always trying to express, and had to be
# hand-maintained to express. A term whose data was captured before it began is
# advance registration: charting it beside settled terms shows a collapse that
# is an artifact of the pull date.

settled_students <- function() {
  mk <- function(term, n, graded, pull) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded)),
    as_of_date = as.Date(pull)
  )
  dplyr::bind_rows(
    mk(202580, 100, 91, "2026-03-07"),   # Fall 2025, pulled long after it began
    mk(202610, 100,  7, "2026-04-20"),   # Spring 2026, began Jan, pulled April
    mk(202660, 100,  0, "2026-04-27"),   # Summer 2026, pulled BEFORE it begins
    mk(202680,  70,  0, "2026-06-18")    # Fall 2026, pulled BEFORE it begins
  )
}

test_that("a term captured before it began is not a settled term", {
  e <- cedar_data_edges(settled_students())

  expect_equal(e$last_enrolled, 202680L)            # raw extent
  expect_equal(e$last_enrolled_complete, 202610L)   # last settled
  expect_lt(e$last_enrolled_complete, e$last_enrolled)
})

test_that("the three edges are genuinely three different terms", {
  # graded < settled < raw. If any two collapse, a caller will pick the wrong
  # one without noticing.
  e <- cedar_data_edges(settled_students())
  expect_equal(e$last_graded, 202580L)
  expect_true(e$last_graded < e$last_enrolled_complete)
  expect_true(e$last_enrolled_complete < e$last_enrolled)
})

test_that("a genuine enrollment decline is NOT treated as an unfinished term", {
  # The failure mode a size-ratio rule would have. Fall 2026 here is settled
  # (pulled well after it began) but only a third the usual size — a real drop.
  # It must survive as the edge, so the decline is visible rather than truncated.
  declining <- dplyr::bind_rows(
    dplyr::filter(settled_students(), term %in% c(202580L, 202610L)),
    tibble::tibble(term = rep(202680L, 30), final_grade = NA_character_,
                   as_of_date = as.Date("2026-10-01"))
  )
  e <- cedar_data_edges(declining)
  expect_equal(e$last_enrolled_complete, 202680L)
})

test_that("min_days_after_start clears add/drop rather than the first day", {
  # A pull on day 1 of a term catches the tail of registration churn.
  day_one <- tibble::tibble(term = rep(202680L, 50), final_grade = NA_character_,
                            as_of_date = as.Date("2026-08-16"))
  expect_null(cedar_data_edges(day_one, min_days_after_start = 14L)$last_enrolled_complete)
  expect_equal(cedar_data_edges(day_one, min_days_after_start = 0L)$last_enrolled_complete,
               202680L)
})

test_that("without as_of_date the settled edge is NULL, not the raw maximum", {
  # Failing closed: silently returning the raw edge would reintroduce the
  # in-flight term into enrollment reports.
  no_dates <- dplyr::select(settled_students(), -as_of_date)
  expect_null(cedar_data_edges(no_dates)$last_enrolled_complete)
  expect_equal(cedar_data_edges(no_dates)$last_enrolled, 202680L)
})

test_that("longitudinal analyses stop at the complete-term edge", {
  edges <- list(
    last_enrolled = 202680L,
    last_enrolled_complete = 202660L,
    last_graded = 202610L
  )

  expect_equal(cedar_longitudinal_edge(edges), 202660L)
  expect_equal(cedar_longitudinal_edge(edges, grade_dependent = TRUE), 202610L)
  expect_match(cedar_longitudinal_edge_note(edges), "Fall 2026")
  expect_match(cedar_longitudinal_edge_note(edges), "excluded here")
})

test_that("longitudinal edge fails closed without a complete enrollment term", {
  expect_null(cedar_longitudinal_edge(list(
    last_enrolled = 202680L,
    last_enrolled_complete = NULL,
    last_graded = 202610L
  )))
})

test_that("the enrolled note explains why the newest term is held back", {
  note <- cedar_edge_note(cedar_data_edges(settled_students()), "enrolled")
  expect_match(note, "Spring 2026")
  expect_match(note, "Fall 2026")
  expect_match(note, "artifact of the pull date")
})
