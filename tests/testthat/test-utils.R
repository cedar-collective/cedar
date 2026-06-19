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
