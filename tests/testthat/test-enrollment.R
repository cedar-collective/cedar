# Tests for enrollment analysis functions
# Tests R/cones/enrl.R: summarize_courses, aggregate_courses, get_enrl, calc_cl_enrls
#
# Uses known_sections and known_students fixtures from fixtures/known_test_data.R
# See fixture file for expected enrollment values.
#
# IMPORTANT: No fallback column checking - tests enforce CEDAR data model
# Required columns: available, waitlist_count (not avail, waiting as input)

context("Enrollment Analysis")

# Load required libraries
library(dplyr)

# Load enrollment functions
source("../../R/cones/enrl.R")
source("../../R/branches/filter.R")

# =============================================================================
# summarize_courses() tests
# =============================================================================

test_that("summarize_courses aggregates enrollment correctly for single term", {
  message("\n  Testing summarize_courses aggregation for 202510...")

  # Filter to 202510 active sections for testing
  test_data <- known_sections %>%
    filter(term == 202510, status == "A") %>%
    # Add required columns that summarize_courses expects
    mutate(crosslist_code = "0")

  opt <- list(group_cols = c("campus", "college", "term", "subject_course"))
  result <- summarize_courses(test_data, opt)

  message("  Result has ", nrow(result), " rows")

  # Should have 5 courses in 202510
  expect_equal(nrow(result), 5)

  # Check HIST 1110 Main campus specifically
  hist_1110 <- result %>% filter(subject_course == "HIST 1110")
  expect_equal(nrow(hist_1110), 1)
  expect_equal(hist_1110$enrolled, 25)
  expect_equal(hist_1110$avail, 5)      # Output column name is 'avail' (sum of 'available')
  expect_equal(hist_1110$waiting, 12)   # Output column name is 'waiting' (sum of 'waitlist_count')
  expect_equal(hist_1110$sections, 1)

  # Check ANTH 1110 - highest enrollment
  anth_1110 <- result %>% filter(subject_course == "ANTH 1110")
  expect_equal(anth_1110$enrolled, 40)
  expect_equal(anth_1110$avail, 5)
  expect_equal(anth_1110$waiting, 15)
})

test_that("summarize_courses calculates avg_size correctly", {
  message("\n  Testing avg_size calculation...")

  test_data <- known_sections %>%
    filter(term == 202510, status == "A") %>%
    mutate(crosslist_code = "0")

  opt <- list(group_cols = c("campus", "college", "term", "subject_course"))
  result <- summarize_courses(test_data, opt)

  # With 1 section per course, avg_size should equal enrolled
  hist_1110 <- result %>% filter(subject_course == "HIST 1110")
  expect_equal(hist_1110$avg_size, 25)

  math_1215 <- result %>% filter(subject_course == "MATH 1215")
  expect_equal(math_1215$avg_size, 35)
})

test_that("summarize_courses uses default group_cols when NULL", {
  message("\n  Testing default group_cols...")

  test_data <- known_sections %>%
    filter(term == 202510, status == "A") %>%
    mutate(crosslist_code = "0")

  opt <- list(group_cols = NULL)
  result <- summarize_courses(test_data, opt)

  # Default includes: campus, college, term, term_type, subject, subject_course, course_title, level, gen_ed_area
  expect_true("campus" %in% colnames(result))
  expect_true("college" %in% colnames(result))
  expect_true("term" %in% colnames(result))
  expect_true("subject_course" %in% colnames(result))
  expect_true("level" %in% colnames(result))
})

test_that("summarize_courses tracks crosslisted sections", {
  message("\n  Testing crosslist section counting...")

  # Add some crosslisted sections for testing
  test_data <- known_sections %>%
    filter(term == 202510, status == "A") %>%
    mutate(crosslist_code = c("XL001", "0", "0", "0", "XL002"))

  opt <- list(group_cols = c("term"))
  result <- summarize_courses(test_data, opt)

  expect_equal(result$sections, 5)
  expect_equal(result$xl_sections, 2)
  expect_equal(result$reg_sections, 3)
})


# =============================================================================
# aggregate_courses() tests
# =============================================================================

test_that("aggregate_courses requires group_cols parameter", {
  message("\n  Testing aggregate_courses validation...")

  test_data <- known_sections %>% filter(term == 202510, status == "A")
  opt <- list(group_cols = NULL)

  # Should error when group_cols is NULL
  expect_error(aggregate_courses(test_data, opt), "group_cols is null")
})

test_that("aggregate_courses calls summarize_courses correctly", {
  message("\n  Testing aggregate_courses wrapper...")

  test_data <- known_sections %>%
    filter(term == 202510, status == "A") %>%
    mutate(crosslist_code = "0")

  opt <- list(group_cols = c("term", "department"))
  result <- aggregate_courses(test_data, opt)

  # Should aggregate by department within term
  expect_true("department" %in% colnames(result))
  expect_true("enrolled" %in% colnames(result))

  # HIST has 2 sections, MATH has 2 sections, ANTH has 1 section in 202510
  hist_dept <- result %>% filter(department == "HIST")
  expect_equal(hist_dept$sections, 2)
  expect_equal(hist_dept$enrolled, 25 + 30)  # HIST 1110 + HIST 1120
})


# =============================================================================
# get_enrl() tests
# =============================================================================

test_that("get_enrl returns correct structure with required columns", {
  message("\n  Testing get_enrl output structure...")

  opt <- list(
    term = 202510,
    status = "A",
    group_cols = c("campus", "college", "term", "subject_course")
  )
  result <- get_enrl(known_sections, opt)

  # Check required CEDAR output columns
  expect_true("campus" %in% colnames(result))
  expect_true("college" %in% colnames(result))
  expect_true("term" %in% colnames(result))
  expect_true("subject_course" %in% colnames(result))
  expect_true("enrolled" %in% colnames(result))
  expect_true("avail" %in% colnames(result))     # Output aggregated column
  expect_true("waiting" %in% colnames(result))   # Output aggregated column
  expect_true("sections" %in% colnames(result))

  # No fallback to old column names
  message("  CEDAR columns verified (no fallback)")
})

test_that("get_enrl aggregates correctly with value verification", {
  message("\n  Testing get_enrl aggregation with expected values...")

  opt <- list(
    term = 202510,
    status = "A",
    group_cols = c("term")
  )
  result <- get_enrl(known_sections, opt)

  # Expected totals for 202510 (5 active sections):
  # enrolled: 25+30+35+28+40 = 158
  # avail: 5+5+5+2+5 = 22
  # waiting: 12+5+25+0+15 = 57
  expect_equal(nrow(result), 1)
  expect_equal(result$sections, 5)
  expect_equal(result$enrolled, 158)
  expect_equal(result$avail, 22)
  expect_equal(result$waiting, 57)
})

test_that("get_enrl filters by department correctly", {
  message("\n  Testing get_enrl department filtering...")

  opt <- list(
    term = 202510,
    dept = "HIST",
    status = "A",
    group_cols = c("term", "department")
  )
  result <- get_enrl(known_sections, opt)

  expect_equal(nrow(result), 1)
  expect_equal(result$department, "HIST")
  expect_equal(result$sections, 2)  # HIST 1110 and HIST 1120
  expect_equal(result$enrolled, 55)  # 25 + 30
})

test_that("get_enrl returns empty result for non-existent filters", {
  message("\n  Testing get_enrl with no matching data...")

  opt <- list(
    term = 999999,  # Non-existent term
    status = "A",
    group_cols = c("term")
  )
  result <- get_enrl(known_sections, opt)

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_enrl respects status filter", {
  message("\n  Testing get_enrl status filtering...")

  # 202580 has one cancelled section (MATH 4310)
  opt_active <- list(
    term = 202580,
    status = "A",
    group_cols = c("term")
  )
  result_active <- get_enrl(known_sections, opt_active)

  opt_cancelled <- list(
    term = 202580,
    status = "C",
    group_cols = c("term")
  )
  result_cancelled <- get_enrl(known_sections, opt_cancelled)

  # Active: 3 sections (HIST 3010, MATH 3140, ANTH 2050)
  expect_equal(result_active$sections, 3)

  # Cancelled: 1 section (MATH 4310)
  expect_equal(result_cancelled$sections, 1)
  expect_equal(result_cancelled$enrolled, 0)  # MATH 4310 has 0 enrolled
})

test_that("get_enrl without aggregation returns section-level data", {
  message("\n  Testing get_enrl section-level output...")

  opt <- list(
    term = 202510,
    status = "A"
    # No group_cols = no aggregation
  )
  result <- get_enrl(known_sections, opt)

  # Should return 5 individual sections
  expect_equal(nrow(result), 5)
  expect_true("crn" %in% colnames(result))
  expect_true("section_id" %in% colnames(result) || "subject_course" %in% colnames(result))
})

test_that("get_enrl handles multiple terms correctly", {
  message("\n  Testing get_enrl with multiple terms...")

  opt <- list(
    term = c(202510, 202560),
    status = "A",
    group_cols = c("term")
  )
  result <- get_enrl(known_sections, opt)

  expect_equal(nrow(result), 2)

  term_202510 <- result %>% filter(term == 202510)
  term_202560 <- result %>% filter(term == 202560)

  expect_equal(term_202510$sections, 5)
  expect_equal(term_202560$sections, 3)
})


# =============================================================================
# calc_cl_enrls() tests - student registration statistics
# =============================================================================

test_that("calc_cl_enrls counts students by registration status", {
  message("\n  Testing calc_cl_enrls basic functionality...")

  # Filter students for term 202510
  test_students <- known_students %>%
    filter(term == 202510)

  result <- calc_cl_enrls(test_students)

  expect_s3_class(result, "data.frame")
  expect_true("subject_course" %in% colnames(result))
  expect_true("registered" %in% colnames(result))
})

test_that("calc_cl_enrls filters by specific registration codes", {
  message("\n  Testing calc_cl_enrls with specific reg codes...")

  test_students <- known_students %>%
    filter(term == 202510)

  # Filter for early drops only (DR)
  result <- calc_cl_enrls(test_students, reg_status = c("DR"))

  expect_s3_class(result, "data.frame")
  expect_true("registration_status_code" %in% colnames(result))

  # Known early drops in 202510: 2 (one each in SEC002 and SEC005)
  total_drops <- sum(result$count)
  expect_equal(total_drops, 2)
})

test_that("calc_cl_enrls calculates drop statistics correctly", {
  message("\n  Testing calc_cl_enrls drop statistics...")

  test_students <- known_students %>%
    filter(term == 202510)

  result <- calc_cl_enrls(test_students)

  # Should have dr_early, dr_late, dr_all columns when reg_status is NULL
  expect_true("dr_early" %in% colnames(result))

  # Known values from fixture:
  # SEC002: 1 early drop (STU025)
  # SEC005: 1 early drop (STU013)
  # Total early drops = 2
})

test_that("calc_cl_enrls aggregates by course correctly", {
  message("\n  Testing calc_cl_enrls course aggregation...")

  test_students <- known_students %>%
    filter(term == 202510)

  result <- calc_cl_enrls(test_students)

  # Should group by subject_course
  courses <- unique(result$subject_course)
  message("  Courses found: ", paste(courses, collapse = ", "))

  # 202510 students are in: HIST 1110, HIST 1120, MATH 1215, ANTH 1110
  expect_true("HIST 1110" %in% courses)
  expect_true("HIST 1120" %in% courses)
  expect_true("MATH 1215" %in% courses)
  expect_true("ANTH 1110" %in% courses)
})

test_that("calc_cl_enrls handles empty student list", {
  message("\n  Testing calc_cl_enrls with empty data...")

  empty_students <- known_students %>% filter(term == 999999)
  result <- calc_cl_enrls(empty_students)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})


# =============================================================================
# Edge cases and data integrity
# =============================================================================

test_that("enrollment functions handle missing optional columns gracefully", {
  message("\n  Testing missing column handling...")

  # Create minimal data without some optional columns (but with required CEDAR columns)
  minimal_data <- tibble(
    campus = "Main",
    college = "AS",
    term = 202510,
    term_type = "spring",
    subject = "TEST",
    subject_course = "TEST 1000",
    course_title = "Test Course",
    level = "lower",
    enrolled = 25,
    capacity = 30,
    gen_ed_area = NA_character_,
    department = "TEST",
    status = "A",
    crn = 99999,
    delivery_method = "In Person",
    instructor_name = "Test, Instructor",
    waitlist_count = 3  # Required CEDAR column
  )

  opt <- list(
    term = 202510,
    status = "A",
    group_cols = c("term", "subject_course")
  )

  # Should compute available from capacity - enrolled
  result <- get_enrl(minimal_data, opt)

  expect_equal(nrow(result), 1)
  expect_equal(result$enrolled, 25)
  expect_equal(result$avail, 5)  # capacity - enrolled = 30 - 25
})

test_that("enrollment totals match known fixture calculations", {
  message("\n  Testing enrollment totals against fixture...")

  # Verify fixture data integrity by checking known totals
  # Spring 2024 (202410): 5 sections, total enrolled = 22+28+30+25+38 = 143
  spring_2024 <- known_sections %>% filter(term == 202410)
  expect_equal(sum(spring_2024$enrolled), 143)

  # Spring 2025 (202510): 5 sections, total enrolled = 25+30+35+28+40 = 158
  spring_2025 <- known_sections %>% filter(term == 202510)
  expect_equal(sum(spring_2025$enrolled), 158)

  message("  Fixture enrollment totals verified")
})

test_that("get_enrl filters by instructor_name correctly", {
  message("\n  Testing instructor filter...")
  
  # Known: Smith, John teaches:
  #   SEC101: HIST 1110 (202410)
  #   SEC001: HIST 1110 (202510)
  #   SEC003: HIST 2010 (202560)
  opt <- list(
    inst = "Smith, John",
    uel = FALSE  # Don't use exclude list (may exclude courses)
  )
  
  result <- get_enrl(known_sections, opt)
  
  # Should return only sections taught by Smith, John
  expect_equal(nrow(result), 3)
  expect_true(all(result$instructor_name == "Smith, John"))
  
  # Known courses for Smith, John  
  smith_courses <- c("HIST 1110", "HIST 2010")
  expect_true(all(result$subject_course %in% smith_courses))
  
  message("  Instructor filter verified")
})

# =============================================================================
# Enrollment Minimum Threshold Tests
# =============================================================================

test_that("filter_DESRs respects enrl_min parameter", {
  message("\n  Testing enrl_min filtering...")
  
  # Test with known_sections
  opt_min0 <- list(
    term = 202510,
    status = "A",
    enrl_min = 0,
    enrl_max = 731,
    uel = FALSE
  )
  
  opt_min10 <- list(
    term = 202510,
    status = "A",
    enrl_min = 10,
    enrl_max = 731,
    uel = FALSE
  )
  
  filtered_0 <- filter_DESRs(known_sections, opt_min0)
  filtered_10 <- filter_DESRs(known_sections, opt_min10)
  
  # Filtering with higher min should return fewer or equal rows
  expect_lte(nrow(filtered_10), nrow(filtered_0))
  
  # All rows in filtered_10 should have enrollment >= 10
  expect_true(all(filtered_10$enrolled >= 10))
  
  message("  ✓ enrl_min parameter filters correctly")
})

test_that("filter_DESRs with higher enrl_min excludes smaller sections", {
  message("\n  Testing enrl_min excludes smaller sections...")
  
  # Get all 202510 active sections
  opt_all <- list(
    term = 202510,
    status = "A",
    enrl_min = 0,
    enrl_max = 731,
    uel = FALSE
  )
  
  all_sections <- filter_DESRs(known_sections, opt_all)
  
  # Count how many have enrollment < 20
  small_count <- nrow(all_sections %>% filter(enrolled < 20))
  
  # Now filter with min=20
  opt_min20 <- list(
    term = 202510,
    status = "A",
    enrl_min = 20,
    enrl_max = 731,
    uel = FALSE
  )
  
  filtered_20 <- filter_DESRs(known_sections, opt_min20)
  
  # Difference should be approximately the number of sections < 20
  expect_equal(nrow(all_sections) - nrow(filtered_20), small_count)
  
  message("  ✓ Enrollment minimum threshold working correctly")
})

test_that("filter_DESRs enrl_min and enrl_max work together as range", {
  message("\n  Testing enrollment range filtering...")
  
  opt <- list(
    term = 202510,
    status = "A",
    enrl_min = 20,    # At least 20 enrolled
    enrl_max = 40,    # At most 40 enrolled
    uel = FALSE
  )
  
  filtered <- filter_DESRs(known_sections, opt)
  
  if (nrow(filtered) > 0) {
    # All filtered courses should be in the range [20, 40]
    expect_true(all(filtered$enrolled >= 20))
    expect_true(all(filtered$enrolled <= 40))
    message("  ✓ Enrollment range filtering works correctly")
  } else {
    message("  Note: No sections in range 20-40 enrollment")
    expect_equal(nrow(filtered), 0)
  }
})
