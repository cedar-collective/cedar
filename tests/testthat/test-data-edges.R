# Tests for R/branches/data-edges.R
#
# CEDAR's local data runs behind the registrar and a term arrives in stages:
# registration months early, grades weeks late. So the last ENROLLED term and
# the last GRADEABLE term are routinely different, and bounding a grade-based
# rate by the enrollment edge yields a confident wrong number rather than an
# error. Measured before this existed: the newest term's DFW rate read 0.3%
# against 6-8% for every other term.

context("Data Edges")


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

test_that("a graded edge that cannot be advanced is an error, not a dropped sentence", {
  # The next-term sentence used to vanish silently when add_term() failed on
  # the edge. The edge is validated upstream, so a value it cannot advance is a
  # bug to surface, not a clause to omit.
  expect_error(
    cedar_edge_note(list(last_graded = "nope", last_enrolled = 202680L), "graded"),
    "last_graded must be a term code"
  )
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

test_that("the app's report edges are the data edges under their app names", {
  r <- cedar_report_edges(settled_students())
  expect_equal(r$edges, cedar_data_edges(settled_students()))
  expect_equal(r$graded_through, 202580L)
  expect_equal(r$report_end_term, 202610L)
  expect_equal(r$report_latest_term, 202680L)
})

test_that("the app's report edges are not capped below the newest registrations", {
  # A term registering ahead of the one the institution is in reaches the
  # descriptive charts the day it lands; the settled rule alone keeps it out of
  # trend comparisons.
  ahead <- dplyr::bind_rows(
    settled_students(),
    tibble::tibble(term = rep(202710L, 40), final_grade = NA_character_,
                   as_of_date = as.Date("2026-10-28"))
  )
  r <- cedar_report_edges(ahead)
  expect_equal(r$report_latest_term, 202710L)
  expect_equal(r$report_end_term, 202610L)
  expect_true(202710L %in% cedar_in_progress_terms(r$edges)$term)
})

test_that("an undeterminable report edge stops startup instead of being guessed", {
  no_dates <- dplyr::select(settled_students(), -as_of_date)
  expect_error(cedar_report_edges(no_dates), "settled edge")
  ungraded <- dplyr::mutate(settled_students(), final_grade = NA_character_)
  expect_error(cedar_report_edges(ungraded), "graded edge")
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


# =============================================================================
# In-progress terms: shown on descriptive charts, labelled, never dropped
# =============================================================================
#
# Descriptive enrollment charts run to last_enrolled. Every term after the graded
# edge is current registration and must be labelled; hiding it made Fall 2026
# vanish from Dept Trends for its first weeks.

test_that("every enrolled term after the graded edge is in progress", {
  ip <- cedar_in_progress_terms(cedar_data_edges(settled_students()))
  # Graded through Fall 2025, so Spring, Summer and Fall 2026 are all unfinished.
  expect_equal(ip$term, c(202610L, 202660L, 202680L))
  # Spring 2026 was pulled after it began; Summer and Fall were not.
  expect_equal(ip$settled, c(TRUE, FALSE, FALSE))
  expect_equal(ip$newest_pull[ip$term == 202680L], as.Date("2026-06-18"))
})

test_that("a fully graded snapshot has no in-progress terms and no note", {
  graded <- settled_students() %>% dplyr::mutate(final_grade = "A")
  ip <- cedar_in_progress_terms(cedar_data_edges(graded))
  expect_equal(nrow(ip), 0)
  expect_null(cedar_in_progress_note(ip))
})

test_that("the in-progress note names the term, its pull date, and filling state", {
  ip <- cedar_in_progress_terms(cedar_data_edges(settled_students()))
  note <- cedar_in_progress_note(ip[ip$term == 202680L, ])
  expect_match(note, "Fall 2026 as of Jun 18, 2026, registration still filling")
  expect_match(note, "last graded term")
})

test_that("in-progress terms fail loudly without edges", {
  expect_error(cedar_in_progress_terms(NULL), "last_enrolled")
})

test_that("a pull settles registration fourteen days after the nominal term start", {
  # Fall 2020's nominal start is Aug 15; add/drop clears by Aug 29.
  expect_equal(cedar_registration_settled(c(202080L, 202080L, NA, 202080L),
                                          as.Date(c("2020-08-28", "2020-08-29", "2020-08-29", NA)),
                                          14L),
               c(FALSE, TRUE, NA, NA))
})


# ── The term dimension (R/branches/cedar-terms.R) ───────────────────────────
# The same edges as per-term flags, beside each term's calendar facts, so a
# reader filters on a column instead of comparing against a startup global.

test_that("the term dimension has one row per term in any table, oldest first", {
  d <- build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees)

  # 201910 has sections and no class list; it is a term, with zero enrollment.
  expect_equal(d$term, c(201910L, 202010L, 202060L, 202080L, 202110L))
  expect_equal(d$enrollment_rows[d$term == 201910L], 0L)
  expect_false(d$is_enrolled[d$term == 201910L])
  expect_equal(d$section_rows[d$term == 201910L], 3L)
  expect_equal(d$enrollment_rows[d$term == 202010L], 133L)
  expect_equal(names(d), CEDAR_TERMS_COLUMNS)
})

test_that("calendar facts come from the term code, and Summer is skipped for regular neighbours", {
  d <- build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees)
  r <- function(t, col) d[[col]][d$term == t]

  expect_equal(r(202010L, "label"), "Spring 2020")
  expect_equal(r(202080L, "acad_year"), "2020-2021")
  expect_equal(r(202010L, "acad_year"), "2019-2020")
  expect_equal(d$season, c("spring", "spring", "summer", "fall", "spring"))
  expect_equal(d$is_regular, c(TRUE, TRUE, FALSE, TRUE, TRUE))
  # calendar: Spring -> Summer -> Fall
  expect_equal(r(202010L, "next_term"), 202060L)
  expect_equal(r(202060L, "prev_term"), 202010L)
  # regular: Spring -> Fall, and a Summer term's next regular term is the Fall
  expect_equal(r(202010L, "next_regular_term"), 202080L)
  expect_equal(r(202080L, "prev_regular_term"), 202010L)
  expect_equal(r(202060L, "next_regular_term"), 202080L)
  expect_equal(r(202060L, "prev_regular_term"), 202010L)
})

test_that("first day and census come from the term's sections, by the most common value", {
  d <- build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees)
  # The fixture stamps census1 = as_of_date + 15 on every section, so one value.
  expect_equal(d$census_date[d$term == 202010L], as.Date("2020-01-28"))
  expect_equal(d$start_date[d$term == 202010L],
               as.Date(names(which.max(table(test_sections$start_date[test_sections$term == 202010L])))))
  expect_false(any(is.na(d$start_date[d$section_rows > 0L])))
})

test_that("degrees count awarded only, and the degree edge flags the terms", {
  d <- build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees)
  expect_equal(d$degrees_awarded[d$term %in% c(202060L, 202080L, 202110L)], c(4L, 4L, 0L))
  # last_degree is 202080 (202110's degrees are Pending)
  expect_equal(d$has_degrees, c(TRUE, TRUE, TRUE, TRUE, FALSE))
})

test_that("an edge the data cannot determine is NA on every row, never FALSE", {
  # Every fixture term was pulled within days of its start, so the settled edge
  # is NULL. The dimension must say unknown, not "nothing is settled".
  e <- cedar_data_edges(test_students, degrees = test_degrees)
  expect_null(e$last_enrolled_complete)
  d <- build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees, edges = e)
  expect_true(all(is.na(d$is_settled)))
  # The graded edge exists (202110), so is_graded is known.
  expect_equal(d$is_graded, c(FALSE, TRUE, TRUE, TRUE, TRUE))
  expect_false(any(is.na(d$in_progress)))
})

test_that("the flags are the edges: settled, graded and in progress disagree where the edges do", {
  s <- settled_students()
  e <- cedar_data_edges(s)
  d <- build_cedar_terms(s, edges = e)
  r <- function(col) setNames(d[[col]], d$term)

  expect_equal(unname(r("is_settled")),  c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(unname(r("is_graded")),   c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(unname(r("in_progress")), c(FALSE, TRUE, TRUE, TRUE))
  expect_equal(d$term[d$is_settled], c(202580L, 202610L))
  expect_equal(max(d$term[d$is_settled]), e$last_enrolled_complete)
  expect_equal(max(d$term[d$is_graded]), e$last_graded)
  # no sections supplied: no dates, no upcoming term
  expect_true(all(is.na(d$start_date)))
  expect_false(any(d$is_upcoming))
})

test_that("a term with a schedule and no class list after the last enrolled term is upcoming", {
  ahead <- test_sections %>%
    dplyr::filter(term == 202110L) %>%
    dplyr::mutate(term = 202180L, start_date = start_date + 210L, census1 = census1 + 210L)
  d <- build_cedar_terms(test_students, sections = dplyr::bind_rows(test_sections, ahead),
                         degrees = test_degrees)
  expect_true(d$is_upcoming[d$term == 202180L])
  expect_false(d$is_enrolled[d$term == 202180L])
  expect_equal(sum(d$is_upcoming), 1L)
  # a past term with sections only is not upcoming
  expect_false(d$is_upcoming[d$term == 201910L])
})

test_that("a Fall or Spring with no class list inside the enrolled run is a row with zero enrollment, reported", {
  # Drop Fall 2020 from every table: Spring 2020 and Spring 2021 remain, so
  # Fall 2020 is a gap, which the synthetic institution has by design and a
  # production refresh would have only if a pull were missing. It must be a
  # row (next_regular_term always names a row) that no reader can mistake
  # for a term nobody attended: zero enrollment, never settled or graded.
  expect_message(
    d <- build_cedar_terms(dplyr::filter(test_students, term != 202080L),
                           sections = dplyr::filter(test_sections, term != 202080L),
                           degrees = dplyr::filter(test_degrees, term != 202080L)),
    "no class list between Spring 2020 and Spring 2021: Fall 2020")
  expect_equal(d$term, c(201910L, 202010L, 202060L, 202080L, 202110L))
  g <- d[d$term == 202080L, ]
  expect_equal(g$enrollment_rows, 0L)
  expect_equal(g$section_rows, 0L)
  expect_false(g$is_enrolled)
  expect_false(g$is_graded)
  expect_false(g$in_progress)
  expect_false(g$is_upcoming)
  expect_equal(d$next_regular_term[d$term == 202010L], 202080L)
  expect_equal(d$prev_regular_term[d$term == 202110L], 202080L)
  # The complete fixture has no gap and says nothing.
  expect_no_message(build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees,
                                      edges = cedar_data_edges(test_students, degrees = test_degrees)),
                    message = "no class list")
})

test_that("the dimension fails loudly on a repeated term, a bad code, or a missing regular row", {
  d <- build_cedar_terms(test_students, sections = test_sections, degrees = test_degrees)
  expect_error(validate_cedar_terms(dplyr::bind_rows(d, d[2, ])), "repeats term")
  expect_error(validate_cedar_terms(dplyr::mutate(d, term = dplyr::if_else(term == 202060L, 202050L, term))),
               "not YYYYSS")
  expect_error(validate_cedar_terms(dplyr::filter(d, term != 202080L)), "no row for.*Fall 2020")
  expect_error(build_cedar_terms(test_students, sections = dplyr::select(test_sections, -census1)),
               "census1")
  expect_error(build_cedar_terms(test_students[0, ]), "non-empty")
})

test_that("regular_terms_between() walks Fall and Spring and steps a Summer endpoint inward", {
  expect_equal(regular_terms_between(202010L, 202110L), c(202010L, 202080L, 202110L))
  expect_equal(regular_terms_between(202060L, 202110L), c(202080L, 202110L))
  expect_equal(regular_terms_between(202010L, 202060L), 202010L)
  expect_equal(regular_terms_between(202080L, 202080L), 202080L)
  expect_equal(regular_terms_between(202110L, 202010L), integer(0))
  expect_error(regular_terms_between(NA, 202010L), "two term codes")
})
