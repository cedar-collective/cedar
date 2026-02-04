# Tests for utility functions

library(withr)
library(lubridate)

# Load term lists required by utils
source("../../R/lists/terms.R")
# Load utility functions under test
source("../../R/branches/utils.R")

test_that("update_codes replaces legacy dept codes", {
  df <- data.frame(code = c("CCS", "PSY", "SOC", "MATH"), stringsAsFactors = FALSE)
  updated <- update_codes(df, "code")
  expect_equal(updated$code, c("CCST", "PSYC", "SOCI", "MATH"))
})

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
  expect_equal(next_no_summer$next_term, c("202410", "202380", "202380"))

  next_with_summer <- add_next_term_col(df, term, summer = TRUE)
  expect_equal(next_with_summer$next_term, c("202410", "202360", "202380"))
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

test_that("term bins and term-to-string mapping work with provided lookup", {
  # Use production term globals from terms.R
  df <- data.frame(term = c("202310", "202380"), stringsAsFactors = FALSE)
  binned <- add_term_bins(df, "term")
  expect_equal(binned$term_bin, c(1, 3))
  expect_equal(term_code_to_str(202310), "Spring 2023")
})

test_that("term_code_to_date returns correct date", {
  expect_equal(term_code_to_date("202380"), as_date("2023-09-10"))
  expect_equal(term_code_to_date("202310"), as_date("2023-02-10"))
  expect_equal(term_code_to_date("202360"), as_date("2023-06-10"))
})

test_that("department lookup from course code works", {
  old_map <- if (exists("subj_to_dept_map", inherits = TRUE)) get("subj_to_dept_map", inherits = TRUE) else NULL
  subj_to_dept_map <<- list(ENGL = "ENGL", ANTH = "ANTH")
  withr::defer({
    if (is.null(old_map)) rm(subj_to_dept_map, inherits = TRUE) else subj_to_dept_map <<- old_map
  })

  expect_equal(get_dept_from_course("ENGL 1110"), "ENGL")
  expect_equal(get_dept_from_course("ANTH 1155"), "ANTH")
})

test_that("is_docker returns a single logical value", {
  res <- is_docker()
  expect_true(is.logical(res) && length(res) == 1)
})
