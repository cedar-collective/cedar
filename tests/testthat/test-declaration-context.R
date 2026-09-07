# Tests for R/cones/declaration-context.R
#
# get_declaration_context() answers one question: where were students — in
# credits and in prior coursework — at the moment they first declared the focal
# program?
#
# Fixture facts these tests rely on (fixtures/designed_test_data.R):
#   STU-HD-*  HIST students with is_pre_major = FALSE — these are the declarers
#   STU-HP-*  HIST pre-majors with is_pre_major = TRUE — these never declare
#   HIST program rows exist in 202010, 202060, and 202080
#
# The population argument is this function's input contract rather than domain
# data, so it is built locally here; the programs/students rows come from the
# shared fixture.

hist_ids <- unique(test_programs$student_id[test_programs$dept_code == "HIST"])

hist_population <- tibble::tibble(
  student_id       = hist_ids,
  population_label = "HIST",
  first_unm_term   = 202010L
)

decl_context <- function(population = hist_population, opt = list(min_n = 1L),
                         term_credits = NULL, focal_subjects = "HIST") {
  suppressMessages(get_declaration_context(
    programs       = test_programs,
    students       = test_students,
    population     = population,
    focal_subjects = focal_subjects,
    opt            = opt,
    term_credits   = term_credits
  ))
}


test_that("pre-major rows never count as a declaration", {
  result <- decl_context()

  declared_ids <- unique(test_programs$student_id[
    test_programs$dept_code == "HIST" &
      test_programs$program_type %in% c("Major", "Second Major") &
      !test_programs$is_pre_major
  ])
  pre_only_ids <- setdiff(hist_ids, declared_ids)

  # Every HIST student who is only ever a pre-major must be absent from the
  # declarer count; the fixture has such students, or this test proves nothing.
  expect_gt(length(pre_only_ids), 0)
  expect_equal(result$n_declarers, length(declared_ids))
})


test_that("credit position is NA without term_credits rather than read off the frozen columns", {
  # The field reliability contract: inst_credits_attempted / overall_credits_*
  # on cedar_programs are stamped at the pull and frozen across a student's
  # history. When the trustworthy class-list series is absent this function must
  # return NA, not fall back to those columns. A missing number is visible
  # downstream; a wrong one is not.
  result <- decl_context(term_credits = NULL)

  expect_true(is.na(result$credits$mean_inst))
  expect_true(is.na(result$credits$median_inst))
  expect_true(is.na(result$credits$mean_overall))
  expect_true(is.na(result$credits$median_overall))
})


test_that("terms to declaration are counted from the population's first UNM term", {
  result <- decl_context()

  # first_unm_term is 202010 for the whole population above, so a student who
  # declared in 202010 is at 0 terms and the mean is >= 0 and finite.
  expect_false(is.na(result$credits$mean_terms))
  expect_gte(result$credits$mean_terms, 0)
})


test_that("prior coursework splits on focal subject", {
  # These declarers only took HIST courses before declaring, so scoping the
  # focal subject to HIST puts every course in courses_focal, and scoping it to
  # anything else moves that same set wholesale into courses_other. Asserting
  # both directions is what makes this a test of the split rather than of one
  # table happening to be populated.
  as_hist  <- decl_context(focal_subjects = "HIST")
  as_other <- decl_context(focal_subjects = "MATH")

  expect_gt(nrow(as_hist$courses_focal), 0)
  expect_true(all(startsWith(as_hist$courses_focal$subject_course, "HIST")))
  expect_equal(nrow(as_hist$courses_other), 0L)

  expect_equal(nrow(as_other$courses_focal), 0L)
  expect_setequal(as_other$courses_other$subject_course,
                  as_hist$courses_focal$subject_course)
})


test_that("min_n is a floor on students per course", {
  loose  <- decl_context(opt = list(min_n = 1L))
  strict <- decl_context(opt = list(min_n = 999L))

  expect_gt(nrow(loose$courses_focal), 0)
  expect_true(all(loose$courses_focal$n_students >= 1L))
  expect_equal(nrow(strict$courses_focal), 0L)
  expect_equal(nrow(strict$courses_other), 0L)
})


test_that("course share is expressed against the declarer count", {
  result <- decl_context(opt = list(min_n = 1L))
  courses <- dplyr::bind_rows(result$courses_focal, result$courses_other)

  expect_gt(nrow(courses), 0)
  expect_equal(courses$pct, round(courses$n_students / result$n_declarers, 3))
})


test_that("a population with no declared students returns NULL", {
  pre_only_ids <- setdiff(
    hist_ids,
    unique(test_programs$student_id[
      test_programs$dept_code == "HIST" &
        test_programs$program_type %in% c("Major", "Second Major") &
        !test_programs$is_pre_major
    ])
  )

  result <- decl_context(population = tibble::tibble(
    student_id       = pre_only_ids,
    population_label = "HIST pre-majors",
    first_unm_term   = 202010L
  ))

  expect_null(result)
})
