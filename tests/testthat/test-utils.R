# Tests for utility functions

library(withr)
library(lubridate)

# NOTE: the former `update_codes()` utility was removed; legacy dept-code remapping
# (CCS->CCST, PSY->PSYC, SOC->SOCI, ...) is now data-driven via R/lists/subj_dept_map.R,
# applied during transform-to-cedar.R, and covered by the catalog/transform tests.

test_that("academic year calculation works for fall/spring/summer", {
  df <- data.frame(term = c("202380", "202310", "202360"), stringsAsFactors = FALSE)
  out <- add_acad_year(df, term)
  expect_equal(out$acad_year, c("2023-2024", "2022-2023", "2022-2023"))
})

test_that("prev/next term helpers compute correctly (with and without summer)", {
  df <- data.frame(term = c("202380", "202310", "202360"), stringsAsFactors = FALSE)
  prev_no_summer <- add_prev_term_col(df, term, summer = FALSE)
  expect_equal(prev_no_summer$prev_term, c(202310, 202280, 202310))

  prev_with_summer <- add_prev_term_col(df, term, summer = TRUE)
  expect_equal(prev_with_summer$prev_term, c(202360, 202280, 202310))

  next_no_summer <- add_next_term_col(df, term, summer = FALSE)
  expect_equal(next_no_summer$next_term, c(202410, 202380, 202380))

  next_with_summer <- add_next_term_col(df, term, summer = TRUE)
  expect_equal(next_with_summer$next_term, c(202410, 202360, 202380))
})

test_that("single term arithmetic functions behave", {
  expect_equal(subtract_term("202380", summer = FALSE), 202310)
  expect_equal(subtract_term("202360", summer = FALSE), 202310)
  expect_equal(subtract_term("202310", summer = FALSE), 202280)

  expect_equal(subtract_term("202380", summer = TRUE), 202360)
  expect_equal(add_term("202380", summer = FALSE), 202410)
  expect_equal(add_term("202310", summer = FALSE), 202380)
  expect_equal(add_term("202360", summer = TRUE), 202380)
})

test_that("get_default_reg_term returns the current term until registration is underway", {
  # Flag off: always the current term, regardless of date.
  expect_equal(get_default_reg_term(202610, FALSE, today = as.Date("2026-07-10")), 202610)
  expect_equal(get_default_reg_term(202680, FALSE, today = as.Date("2026-11-01")), 202680)
})

test_that("get_default_reg_term resolves the next registration term when underway", {
  # Spring: Summer until the mid-June cutoff, then Fall.
  expect_equal(get_default_reg_term(202610, TRUE, today = as.Date("2026-05-01")), 202660) # summer
  expect_equal(get_default_reg_term(202610, TRUE, today = as.Date("2026-06-15")), 202660) # on cutoff -> still summer
  expect_equal(get_default_reg_term(202610, TRUE, today = as.Date("2026-06-16")), 202680) # after cutoff -> fall

  # Summer -> Fall and Fall -> next Spring are unambiguous (date irrelevant).
  expect_equal(get_default_reg_term(202660, TRUE, today = as.Date("2026-07-01")), 202680)
  expect_equal(get_default_reg_term(202680, TRUE, today = as.Date("2026-11-01")), 202710)
})

test_that("get_default_reg_term keys the summer cutoff off the term year, not the wall clock", {
  # Current term is Spring 2025; a 2026 wall-clock date must not force the
  # cutover — the 2025 summer window is what matters for a 2025 term.
  expect_equal(get_default_reg_term(202510, TRUE, today = as.Date("2025-05-01")), 202560)
  expect_equal(get_default_reg_term(202510, TRUE, today = as.Date("2025-08-01")), 202580)
})

test_that("resolve_default_term_choice prefers configured defaults with sane fallbacks", {
  choices <- c("Spring 2026" = 202610, "Summer 2026" = 202660, "Fall 2026" = 202680)

  expect_equal(resolve_default_term_choice(choices, default_term = 202680, fallback_term = 202660), 202680)
  expect_equal(resolve_default_term_choice(choices, default_term = 202710, fallback_term = 202660), 202660)
  expect_equal(resolve_default_term_choice(choices, default_term = NULL, fallback_term = NULL), 202680)
  expect_equal(resolve_default_term_choice(c("fall", "spring", choices), default_term = "202680"), 202680)
})

test_that("term type helpers label fall/spring/summer", {
  df <- data.frame(term = c(202380, 202310, 202360))
  typed <- add_term_type_col(df, term)
  expect_equal(typed$term_type, c("fall", "spring", "summer"))

  expect_equal(get_term_type(202380), "fall")
  expect_equal(get_term_type(202310), "spring")
  expect_equal(get_term_type(202360), "summer")
})

test_that("term bins and term-to-string mapping work", {
  df <- data.frame(term = c("202310", "202380"), stringsAsFactors = FALSE)
  binned <- add_term_bins(df, "term")
  # Spring 2023 = 1, Summer 2023 = 2 (skipped in data), Fall 2023 = 3
  expect_equal(binned$term_bin, c(1L, 3L))
  expect_equal(term_code_to_str(202310), "Spring 2023")
  expect_equal(term_code_to_axis_label(c(202310, 202360, 202380)), c("Sp 23", "Su 23", "Fa 23"))
  expect_equal(term_axis_levels(c(202380, 202310, 202360)), c("Sp 23", "Su 23", "Fa 23"))
})

test_that("term_code_to_date returns correct date", {
  expect_equal(term_code_to_date("202380"), as_date("2023-09-10"))
  expect_equal(term_code_to_date("202310"), as_date("2023-02-10"))
  expect_equal(term_code_to_date("202360"), as_date("2023-06-10"))
})

test_that("department lookup from course code works", {
  old_map <- if (exists("subj_to_dept", inherits = TRUE)) get("subj_to_dept", inherits = TRUE) else NULL
  subj_to_dept <<- list(ENGL = "ENGL", ANTH = "ANTH")
  withr::defer({
    if (is.null(old_map)) rm(subj_to_dept, inherits = TRUE) else subj_to_dept <<- old_map
  })

  expect_equal(get_dept_from_course("ENGL 1110"), "ENGL")
  expect_equal(get_dept_from_course("ANTH 1155"), "ANTH")
})

test_that("is_docker returns a single logical value", {
  res <- is_docker()
  expect_true(is.logical(res) && length(res) == 1)
})


# =============================================================================
# validate_population()
# =============================================================================

test_that("validate_population passes silently for a well-formed population", {
  pop <- tibble::tibble(student_id = "S001", population_label = "cohort")
  expect_invisible(validate_population(pop, "test_caller"))
})

test_that("validate_population stops when student_id is missing", {
  pop <- tibble::tibble(population_label = "cohort")
  expect_error(validate_population(pop, "test_caller"),
               regexp = "test_caller.*student_id")
})

test_that("validate_population stops when population_label is missing", {
  pop <- tibble::tibble(student_id = "S001")
  expect_error(validate_population(pop, "test_caller"),
               regexp = "test_caller.*population_label")
})

test_that("validate_population error message names the calling function", {
  pop <- tibble::tibble(student_id = "S001")
  expect_error(validate_population(pop, "get_stopout"),
               regexp = "get_stopout")
})

test_that("validate_population error mentions build_population()", {
  pop <- tibble::tibble(student_id = "S001")
  expect_error(validate_population(pop, "x"),
               regexp = "build_population")
})


# ---------------------------------------------------------------------------
# compute_trend() — canonical slope/direction helper
# ---------------------------------------------------------------------------

test_that("compute_trend classifies direction and returns the OLS slope", {
  up <- compute_trend(c(10, 20, 30))
  expect_equal(unname(up$slope), 10)          # exact OLS slope of a linear series
  expect_equal(up$direction, "up")
  expect_true(nchar(up$arrow) > 0)

  down <- compute_trend(c(80, 72, 65, 58, 50))
  expect_lt(down$slope, 0)
  expect_equal(down$direction, "down")

  # A perfectly flat series has slope ~0, but floating-point noise means it needs a
  # small threshold to classify as "stable" rather than a spurious up/down.
  flat <- compute_trend(c(50, 50, 50, 50, 50), threshold = 0.01)
  expect_equal(unname(flat$slope), 0)
  expect_equal(flat$direction, "stable")
})

test_that("compute_trend drops NAs before fitting", {
  t <- compute_trend(c(40, NA, 50, NA, 60))   # collapses to c(40, 50, 60)
  expect_equal(unname(t$slope), 10)
  expect_equal(t$direction, "up")
})

test_that("compute_trend returns 'unknown' below the min_n point count", {
  one <- compute_trend(42)
  expect_true(is.na(one$slope))
  expect_equal(one$direction, "unknown")

  # min_n is configurable — ui-helpers trend_slope() requires 3 points.
  expect_equal(compute_trend(c(10, 20), min_n = 3)$direction, "unknown")
})

test_that("compute_trend threshold suppresses weak trends", {
  t <- compute_trend(c(50, 51, 50, 51, 50), threshold = 2)
  expect_equal(t$direction, "stable")
})
