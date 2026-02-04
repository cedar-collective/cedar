# Tests for seatfinder functions
# Tests R/cones/seatfinder.R
#
# Uses known_sections fixture from fixtures/known_test_data.R
# See fixture file for expected seatfinder values (year-over-year comparison)
#
# IMPORTANT: No fallback column checking - tests enforce CEDAR data model
# Required input columns: available (not avail)
#
# Tests focus on helper functions that can be tested in isolation.
# The main seatfinder() function has complex dependencies on get_enrl(),
# get_grades(), and cedar_faculty - those require integration testing.

# Source the seatfinder functions
source("../../R/cones/seatfinder.R")

context("Seatfinder")

# =============================================================================
# Helper to prepare term_courses structure from known_sections
# =============================================================================
# Seatfinder expects term_courses as a list with start/end dataframes
# containing: campus, college, subject_course, gen_ed_area

prepare_term_courses <- function(sections, start_term, end_term) {
  cols <- c("campus", "college", "subject_course", "gen_ed_area")

  start_courses <- sections %>%
    filter(term == start_term, status == "A") %>%
    select(all_of(cols)) %>%
    distinct()

  end_courses <- sections %>%
    filter(term == end_term, status == "A") %>%
    select(all_of(cols)) %>%
    distinct()

  list(start = start_courses, end = end_courses)
}

# Helper to prepare enrollment summary from known_sections
# Uses CEDAR column names: available (not avail as input)
prepare_enrl_summary <- function(sections, terms) {
  sections %>%
    filter(term %in% terms, status == "A") %>%
    # Use 'available' column from fixture, rename to 'avail' for seatfinder output format
    select(campus, college, term, subject_course, gen_ed_area, enrolled, capacity, avail = available)
}


# =============================================================================
# get_courses_diff() tests
# =============================================================================

test_that("get_courses_diff returns correct structure", {
  term_courses <- prepare_term_courses(known_sections, 202410, 202510)
  result <- get_courses_diff(term_courses)

  expect_type(result, "list")
  expect_named(result, c("prev", "new"))
  expect_s3_class(result$prev, "data.frame")
  expect_s3_class(result$new, "data.frame")
})

test_that("get_courses_diff identifies discontinued courses correctly (Spring)", {
  # Compare Spring 2024 (202410) vs Spring 2025 (202510)
  term_courses <- prepare_term_courses(known_sections, 202410, 202510)
  result <- get_courses_diff(term_courses)

  # Known: PHYS 1010 was in 202410 but not in 202510 (discontinued)
  expect_equal(nrow(result$prev), 1)
  expect_equal(result$prev$subject_course, "PHYS 1010")
})

test_that("get_courses_diff identifies new courses correctly (Spring)", {
  # Compare Spring 2024 (202410) vs Spring 2025 (202510)
  term_courses <- prepare_term_courses(known_sections, 202410, 202510)
  result <- get_courses_diff(term_courses)

  # Known: MATH 1220 is new in 202510 (not in 202410)
  expect_equal(nrow(result$new), 1)
  expect_equal(result$new$subject_course, "MATH 1220")
})

test_that("get_courses_diff identifies discontinued courses correctly (Fall)", {
  # Compare Fall 2024 (202480) vs Fall 2025 (202580)
  term_courses <- prepare_term_courses(known_sections, 202480, 202580)
  result <- get_courses_diff(term_courses)

  # Known: CHEM 1010 was in 202480 but not in 202580 (discontinued)
  expect_equal(nrow(result$prev), 1)
  expect_equal(result$prev$subject_course, "CHEM 1010")
})

test_that("get_courses_diff identifies new courses correctly (Fall)", {
  # Compare Fall 2024 (202480) vs Fall 2025 (202580)
  term_courses <- prepare_term_courses(known_sections, 202480, 202580)
  result <- get_courses_diff(term_courses)

  # Known: MATH 4310 and ANTH 2050 are new in 202580
  # Note: MATH 4310 has status "C" (cancelled) so only ANTH 2050 should appear
  expect_equal(nrow(result$new), 1)
  expect_equal(result$new$subject_course, "ANTH 2050")
})

test_that("get_courses_diff handles identical course lists", {
  # When both terms have same courses, both prev and new should be empty
  same_courses <- known_sections %>%
    filter(term == 202510, status == "A") %>%
    select(campus, college, subject_course, gen_ed_area) %>%
    distinct()

  term_courses <- list(start = same_courses, end = same_courses)
  result <- get_courses_diff(term_courses)

  expect_equal(nrow(result$prev), 0)
  expect_equal(nrow(result$new), 0)
})

test_that("get_courses_diff handles empty start term", {
  # Edge case: no courses in start term
  term_courses <- prepare_term_courses(known_sections, 999999, 202510)
  result <- get_courses_diff(term_courses)

  # All end term courses should be "new"
  expect_equal(nrow(result$prev), 0)
  expect_equal(nrow(result$new), 5)  # 5 active courses in 202510
})

test_that("get_courses_diff handles empty end term", {
  # Edge case: no courses in end term
  term_courses <- prepare_term_courses(known_sections, 202510, 999999)
  result <- get_courses_diff(term_courses)

  # All start term courses should be "previously offered"
  expect_equal(nrow(result$prev), 5)  # 5 active courses in 202510
  expect_equal(nrow(result$new), 0)
})


# =============================================================================
# get_courses_common() tests
# =============================================================================

test_that("get_courses_common returns courses in both terms (Spring)", {
  term_courses <- prepare_term_courses(known_sections, 202410, 202510)
  enrl_summary <- prepare_enrl_summary(known_sections, c(202410, 202510))
  result <- get_courses_common(term_courses, enrl_summary)

  # Known common courses: HIST 1110, HIST 1120, MATH 1215, ANTH 1110 (4 courses)
  common_courses <- unique(result$subject_course)
  expect_equal(length(common_courses), 4)
  expect_setequal(common_courses, c("HIST 1110", "HIST 1120", "MATH 1215", "ANTH 1110"))

  # Should NOT include discontinued or new courses
  expect_false("PHYS 1010" %in% common_courses)  # only in 202410
  expect_false("MATH 1220" %in% common_courses)  # only in 202510
})

test_that("get_courses_common returns courses in both terms (Fall)", {
  term_courses <- prepare_term_courses(known_sections, 202480, 202580)
  enrl_summary <- prepare_enrl_summary(known_sections, c(202480, 202580))
  result <- get_courses_common(term_courses, enrl_summary)

  # Known common courses: HIST 3010, MATH 3140 (2 courses)
  common_courses <- unique(result$subject_course)
  expect_equal(length(common_courses), 2)
  expect_setequal(common_courses, c("HIST 3010", "MATH 3140"))
})

test_that("get_courses_common calculates enrollment difference (Spring)", {
  term_courses <- prepare_term_courses(known_sections, 202410, 202510)
  enrl_summary <- prepare_enrl_summary(known_sections, c(202410, 202510))
  result <- get_courses_common(term_courses, enrl_summary)

  # Should have enrl_diff_from_last_year column
  expect_true("enrl_diff_from_last_year" %in% colnames(result))

  # Known enrollment changes (from fixture comments):
  # HIST 1110: 25 (2025) vs 22 (2024) = +3
  hist_result <- result %>% filter(subject_course == "HIST 1110", term == 202510)
  expect_equal(hist_result$enrl_diff_from_last_year, 3)

  # MATH 1215: 35 (2025) vs 30 (2024) = +5
  math_result <- result %>% filter(subject_course == "MATH 1215", term == 202510)
  expect_equal(math_result$enrl_diff_from_last_year, 5)

  # ANTH 1110: 40 (2025) vs 38 (2024) = +2
  anth_result <- result %>% filter(subject_course == "ANTH 1110", term == 202510)
  expect_equal(anth_result$enrl_diff_from_last_year, 2)
})

test_that("get_courses_common calculates enrollment difference (Fall)", {
  term_courses <- prepare_term_courses(known_sections, 202480, 202580)
  enrl_summary <- prepare_enrl_summary(known_sections, c(202480, 202580))
  result <- get_courses_common(term_courses, enrl_summary)

  # Known enrollment changes Fall 2024 vs Fall 2025:
  # HIST 3010: 22 (2025) vs 20 (2024) = +2
  hist_result <- result %>% filter(subject_course == "HIST 3010", term == 202580)
  expect_equal(hist_result$enrl_diff_from_last_year, 2)

  # MATH 3140: 15 (2025) vs 12 (2024) = +3
  math_result <- result %>% filter(subject_course == "MATH 3140", term == 202580)
  expect_equal(math_result$enrl_diff_from_last_year, 3)
})

test_that("get_courses_common returns empty for no common courses", {
  # Use non-overlapping terms
  term_courses <- list(
    start = tibble(campus = "Main", college = "AS", subject_course = "FAKE 1000", gen_ed_area = NA),
    end = tibble(campus = "Main", college = "AS", subject_course = "OTHER 2000", gen_ed_area = NA)
  )
  enrl_summary <- tibble(
    campus = character(), college = character(), term = integer(),
    subject_course = character(), gen_ed_area = character(),
    enrolled = integer(), capacity = integer(), avail = integer()
  )

  result <- get_courses_common(term_courses, enrl_summary)
  expect_equal(nrow(result), 0)
})


# =============================================================================
# normalize_inst_method() tests
# =============================================================================

test_that("normalize_inst_method returns data with method column", {
  test_courses <- known_sections %>%
    filter(term == 202510) %>%
    select(subject_course, delivery_method)

  result <- normalize_inst_method(test_courses)

  expect_true("method" %in% colnames(result))
  expect_equal(nrow(result), nrow(test_courses))
})

test_that("normalize_inst_method converts face-to-face variants to f2f", {
  test_courses <- tibble(
    subject_course = c("HIST 1110", "MATH 1215", "ANTH 1110", "HIST 2010"),
    delivery_method = c("0", "ENH", "HYB", "Online")
  )

  result <- normalize_inst_method(test_courses)

  # "0", "ENH", "HYB" should all become "f2f"
  expect_equal(result$method[1], "f2f")  # "0" -> "f2f"
  expect_equal(result$method[2], "f2f")  # "ENH" -> "f2f"
  expect_equal(result$method[3], "f2f")  # "HYB" -> "f2f"

  # Other values preserved as-is
  expect_equal(result$method[4], "Online")
})

test_that("normalize_inst_method preserves original delivery_method column", {
  test_courses <- tibble(
    subject_course = c("HIST 1110"),
    delivery_method = c("ENH")
  )

  result <- normalize_inst_method(test_courses)

  # Original column should still exist unchanged
  expect_equal(result$delivery_method, "ENH")
  # New column should have normalized value
  expect_equal(result$method, "f2f")
})

test_that("normalize_inst_method handles NA delivery methods", {
  test_courses <- tibble(
    subject_course = c("TEST 1000", "TEST 2000"),
    delivery_method = c(NA_character_, "In Person")
  )

  result <- normalize_inst_method(test_courses)

  # NA should stay NA
  expect_true(is.na(result$method[1]))
  # "In Person" should stay as-is (not converted to f2f)
  expect_equal(result$method[2], "In Person")
})

test_that("normalize_inst_method handles empty dataframe", {
  test_courses <- tibble(
    subject_course = character(),
    delivery_method = character()
  )

  result <- normalize_inst_method(test_courses)

  expect_equal(nrow(result), 0)
  expect_true("method" %in% colnames(result))
})


# =============================================================================
# Fixture data integrity tests
# =============================================================================

test_that("known_sections has required columns for seatfinder", {
  required_cols <- c("campus", "college", "term", "subject_course", "gen_ed_area",
                     "enrolled", "capacity", "available", "status", "department")

  missing <- setdiff(required_cols, colnames(known_sections))
  expect_equal(length(missing), 0,
               info = paste("Missing columns:", paste(missing, collapse = ", ")))
})

test_that("known_sections has expected term pairs for year-over-year comparison", {
  terms <- unique(known_sections$term)

  # Should have Spring 2024 and Spring 2025 for comparison

  expect_true(202410 %in% terms, info = "Missing Spring 2024 (202410)")
  expect_true(202510 %in% terms, info = "Missing Spring 2025 (202510)")

  # Should have Fall 2024 and Fall 2025 for comparison
  expect_true(202480 %in% terms, info = "Missing Fall 2024 (202480)")
  expect_true(202580 %in% terms, info = "Missing Fall 2025 (202580)")
})

test_that("known_sections enrollment values are consistent", {
  # Verify available = capacity - enrolled for fixture integrity
  inconsistent <- known_sections %>%
    filter(available != (capacity - enrolled))

  expect_equal(nrow(inconsistent), 0,
               info = "Fixture has inconsistent available/capacity/enrolled values")
})


# =============================================================================
# Main seatfinder() function tests - require integration setup
# =============================================================================
# These tests are skipped by default because seatfinder() requires:
# - get_enrl() from enrl.R (filters and aggregates courses)
# - get_grades() from gradebook.R (calculates DFW rates)
# - cedar_faculty data frame (for instructor job category)
#
# Run these tests with integration test suite or mock the dependencies.

test_that("seatfinder returns expected list structure", {
  skip("seatfinder() requires integration test - depends on get_enrl, get_grades, cedar_faculty")

  # When integration testing:
  # opt <- list(term = "202510")
  # result <- seatfinder(known_students, known_sections, known_faculty, opt)
  #
  # expect_type(result, "list")
  # expect_named(result, c("type_summary", "courses_common", "courses_prev",
  #                        "courses_new", "gen_ed_summary", "gen_ed_likely"))
})

test_that("seatfinder parses single term correctly", {
  skip("Term parsing tested via integration - seatfinder modifies opt internally")

  # When integration testing, verify:
  # opt$term = "202510" results in:
  #   opt$term_start = "202410"
  #   opt$term_end = "202510"
})

test_that("seatfinder parses comma-separated terms correctly", {
  skip("Term parsing tested via integration - seatfinder modifies opt internally")

  # When integration testing, verify:
  # opt$term = "202410,202510" results in:
  #   opt$term_start = "202410"
  #   opt$term_end = "202510"
})

test_that("seatfinder filters gen ed courses correctly", {
  skip("Gen ed filtering requires full seatfinder pipeline")

  # When integration testing, verify:
  # gen_ed_summary only contains courses with non-NA gen_ed_area
  # gen_ed_likely contains courses with avail == 0 and enrolled == 0
})

test_that("seatfinder merges DFW rates correctly", {
  skip("DFW merge requires get_grades() with cedar_faculty")

  # When integration testing, verify:
  # type_summary has dfw_pct column
  # DFW values are numeric and within expected range (0-100)
})
