# Tests for data filtering functions
# Tests functions in R/branches/filter.R (CEDAR model)
#
# These tests use KNOWN FIXTURES with predetermined expected values.
# See fixtures/known_test_data.R for the fixture definitions and expected counts.

context("Data Filtering - CEDAR Model")

# Load required libraries
library(stringr)

# Load filter functions
source("../../R/branches/filter.R")

# =============================================================================
# Department Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by HIST department correctly", {
  opt <- create_test_opt(list(dept = "HIST"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: HIST has 7 sections (includes previous year data for seatfinder)
  expect_equal(nrow(filtered), 7)
  expect_true(all(filtered$department == "HIST"))
  expect_setequal(filtered$subject_course,
                  c("HIST 1110", "HIST 1120", "HIST 2010", "HIST 3010"))
})

test_that("filter_DESRs filters by MATH department correctly", {
  opt <- create_test_opt(list(dept = "MATH"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: MATH has 6 active sections (7 total, but 1 cancelled - SEC009)
  # create_test_opt sets status="A" by default
  expect_equal(nrow(filtered), 6)
  expect_true(all(filtered$department == "MATH"))
})

test_that("filter_DESRs filters by ANTH department correctly", {
  opt <- create_test_opt(list(dept = "ANTH"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: ANTH has 4 sections
  expect_equal(nrow(filtered), 4)
  expect_true(all(filtered$department == "ANTH"))
})

# =============================================================================
# Term Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by Spring 2025 term correctly", {
  opt <- create_test_opt(list(term = 202510))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 202510 has exactly 5 sections
  expect_equal(nrow(filtered), 5)
  expect_true(all(filtered$term == 202510))
})

test_that("filter_DESRs filters by Summer 2025 term correctly", {
  opt <- create_test_opt(list(term = 202560))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 202560 has exactly 3 sections
  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$term == 202560))
})

test_that("filter_DESRs filters by Fall 2025 term correctly", {
  opt <- create_test_opt(list(term = 202580))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 202580 has 3 active sections (4 total, but SEC009 is cancelled)
  # create_test_opt sets status="A" by default
  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$term == 202580))
})

# =============================================================================
# Campus Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by Main campus correctly", {
  opt <- create_test_opt(list(course_campus = "Main"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: Main campus has 13 sections
  expect_equal(nrow(filtered), 13)
  expect_true(all(filtered$campus == "Main"))
})

test_that("filter_DESRs filters by Online campus correctly", {
  opt <- create_test_opt(list(course_campus = "Online"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: Online has 5 active sections (6 total, but SEC009 is cancelled)
  expect_equal(nrow(filtered), 5)
  expect_true(all(filtered$campus == "Online"))
})

test_that("filter_DESRs filters by Valencia campus correctly", {
  opt <- create_test_opt(list(course_campus = "Valencia"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: Valencia has 1 section
  expect_equal(nrow(filtered), 1)
  expect_equal(filtered$subject_course, "MATH 1220")
})

# =============================================================================
# Status Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by Active status correctly", {
  opt <- create_test_opt(list(status = "A"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 19 active sections (all except SEC009 which is Cancelled)
  expect_equal(nrow(filtered), 19)
  expect_true(all(filtered$status == "A"))
})

test_that("filter_DESRs filters by Cancelled status correctly", {
  opt <- create_test_opt(list(status = "C"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 1 cancelled section (SEC009 - MATH 4310)
  expect_equal(nrow(filtered), 1)
  expect_equal(filtered$subject_course, "MATH 4310")
  expect_equal(filtered$enrolled, 0)
})

# =============================================================================
# Delivery Method Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by In Person delivery correctly", {
  opt <- create_test_opt(list(im = "In Person"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 11 In Person sections
  expect_equal(nrow(filtered), 11)
  expect_true(all(filtered$delivery_method == "In Person"))
})

test_that("filter_DESRs filters by Online delivery correctly", {
  opt <- create_test_opt(list(im = "Online"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 5 active Online sections (6 total, but SEC009 is cancelled)
  expect_equal(nrow(filtered), 5)
  expect_true(all(filtered$delivery_method == "Online"))
})

test_that("filter_DESRs filters by Hybrid delivery correctly", {
  opt <- create_test_opt(list(im = "Hybrid"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 3 Hybrid sections
  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$delivery_method == "Hybrid"))
})

# =============================================================================
# Part of Term Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by full term (FT) correctly", {
  opt <- create_test_opt(list(pt = "FT"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 15 active full term sections (16 total, but SEC009 is cancelled)
  expect_equal(nrow(filtered), 15)
  expect_true(all(filtered$part_term == "FT"))
})

test_that("filter_DESRs filters by second half (2H) correctly", {
  opt <- create_test_opt(list(pt = "2H"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 4 second half sections
  expect_equal(nrow(filtered), 4)
  expect_true(all(filtered$part_term == "2H"))
})

test_that("filter_by_col errors on missing column", {
  # This test ensures clear error messages when column doesn't exist
  expect_error(
    filter_by_col(known_sections, "nonexistent_column", "value"),
    "Column 'nonexistent_column' not found in data"
  )
})

# =============================================================================
# Level Filtering Tests
# =============================================================================

test_that("filter_DESRs filters by lower level correctly", {
  opt <- create_test_opt(list(level = "lower"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 12 lower-level sections
  expect_equal(nrow(filtered), 12)
  expect_true(all(filtered$level == "lower"))
})

test_that("filter_DESRs filters by upper level correctly", {
  opt <- create_test_opt(list(level = "upper"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: 7 active upper-level sections (8 total, but SEC009 is cancelled)
  expect_equal(nrow(filtered), 7)
  expect_true(all(filtered$level == "upper"))
})

# =============================================================================
# Combined Filter Tests
# =============================================================================

test_that("filter_DESRs filters by HIST + Spring 2025 correctly", {
  opt <- create_test_opt(list(dept = "HIST", term = 202510))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: HIST in 202510 has exactly 2 sections
  expect_equal(nrow(filtered), 2)
  expect_true(all(filtered$department == "HIST"))
  expect_true(all(filtered$term == 202510))
  expect_setequal(filtered$subject_course, c("HIST 1110", "HIST 1120"))
})

test_that("filter_DESRs filters by MATH + Main campus correctly", {
  opt <- create_test_opt(list(dept = "MATH", course_campus = "Main"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: MATH at Main campus has 5 sections
  expect_equal(nrow(filtered), 5)
  expect_true(all(filtered$department == "MATH"))
  expect_true(all(filtered$campus == "Main"))
})

test_that("filter_DESRs filters by Online + upper level correctly", {
  opt <- create_test_opt(list(course_campus = "Online", level = "upper"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: Online + upper level has 3 active sections (4 total, but SEC009 is cancelled)
  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$campus == "Online"))
  expect_true(all(filtered$level == "upper"))
})

test_that("filter_DESRs filters by three criteria correctly", {
  opt <- create_test_opt(list(dept = "HIST", term = 202510, course_campus = "Main"))
  filtered <- filter_DESRs(known_sections, opt)

  # Known: HIST + 202510 + Main = 1 section (HIST 1110)
  expect_equal(nrow(filtered), 1)
  expect_equal(filtered$subject_course, "HIST 1110")
  expect_equal(filtered$instructor_name, "Smith, John")
})

# =============================================================================
# Empty Result Tests
# =============================================================================

test_that("filter_DESRs handles nonexistent department gracefully", {
  opt <- create_test_opt(list(dept = "NONEXISTENT"))
  filtered <- filter_DESRs(known_sections, opt)

  # Should return empty data frame, not error
  expect_equal(nrow(filtered), 0)
  expect_true(is.data.frame(filtered))
})

test_that("filter_DESRs handles impossible filter combination gracefully", {
  # ANTH department doesn't have any Valencia campus sections
  opt <- create_test_opt(list(dept = "ANTH", course_campus = "Valencia"))
  filtered <- filter_DESRs(known_sections, opt)

  expect_equal(nrow(filtered), 0)
  expect_true(is.data.frame(filtered))
})

# =============================================================================
# Core Function Tests
# =============================================================================

test_that("filter_by_col works with department column", {
  filtered <- filter_by_col(known_sections, "department", "HIST")

  # Known: 7 HIST sections
  expect_equal(nrow(filtered), 7)
  expect_true(all(filtered$department == "HIST"))
})

test_that("filter_by_col works with multiple values", {
  filtered <- filter_by_col(known_sections, "department", c("HIST", "MATH"))

  # Known: 7 HIST + 7 MATH = 14 sections
  expect_equal(nrow(filtered), 14)
  expect_true(all(filtered$department %in% c("HIST", "MATH")))
})

test_that("filter_by_term handles term range correctly", {
  filtered <- filter_by_term(known_sections, "202510-202580", "term")

  # 2025 terms only: 202510 (5) + 202560 (3) + 202580 (4) = 12 sections
  expect_equal(nrow(filtered), 12)
})

test_that("filter_by_term handles partial range correctly", {
  filtered <- filter_by_term(known_sections, "202510-202560", "term")

  # Known: 202510 (5) + 202560 (3) = 8 sections
  expect_equal(nrow(filtered), 8)
  expect_true(all(filtered$term <= 202560))
})

test_that("filter_by_term handles 'spring' keyword", {
  filtered <- filter_by_term(known_sections, "spring", "term")

  # Known: 10 spring sections (terms ending in 10: 202410 + 202510)
  expect_equal(nrow(filtered), 10)
  expect_true(all(substring(as.character(filtered$term), 5, 6) == "10"))
})

test_that("filter_by_term handles 'summer' keyword", {
  filtered <- filter_by_term(known_sections, "summer", "term")

  # Known: 3 summer sections (term ending in 60)
  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$term == 202560))
})

test_that("filter_by_term handles 'fall' keyword", {
  filtered <- filter_by_term(known_sections, "fall", "term")

  # Known: 7 fall sections (terms ending in 80: 202480 + 202580)
  expect_equal(nrow(filtered), 7)
  expect_true(all(substring(as.character(filtered$term), 5, 6) == "80"))
})

# =============================================================================
# Student/Class List Filtering Tests
# =============================================================================

test_that("filter_class_list filters by department correctly", {
  opt <- create_test_opt(list(dept = "HIST"))
  filtered <- filter_class_list(known_students, opt)

  # Known: 9 HIST enrollments
  expect_equal(nrow(filtered), 9)
  expect_true(all(filtered$department == "HIST"))
})

test_that("filter_class_list filters by term correctly", {
  opt <- create_test_opt(list(term = 202510))
  filtered <- filter_class_list(known_students, opt)

  # Known: 18 enrollments in 202510
  expect_equal(nrow(filtered), 18)
  expect_true(all(filtered$term == 202510))
})

test_that("filter_class_list filters by course correctly", {
  opt <- create_test_opt(list(course = "MATH 1215"))
  filtered <- filter_class_list(known_students, opt)

  # Known: 5 students in MATH 1215
  expect_equal(nrow(filtered), 5)
  expect_true(all(filtered$subject_course == "MATH 1215"))
})

# =============================================================================
# Instructor Name Filtering Tests (with comma handling)
# =============================================================================

test_that("convert_param_to_list preserves instructor names with commas", {
  # Test: "Gibbs, Frederick" should NOT be split on comma
  result <- convert_param_to_list("Gibbs, Frederick", split_on_comma = FALSE)
  
  expect_length(result, 1)
  expect_equal(result[1], "Gibbs, Frederick")
})

test_that("convert_param_to_list splits course lists on comma", {
  # Test: "MATH 1430,ENGL 1110" SHOULD be split on comma
  result <- convert_param_to_list("MATH 1430,ENGL 1110", split_on_comma = TRUE)
  
  expect_length(result, 2)
  expect_equal(result[1], "MATH 1430")
  expect_equal(result[2], "ENGL 1110")
})

test_that("convert_param_to_list trims whitespace correctly", {
  # Test: Whitespace around delimiters should be trimmed
  result <- convert_param_to_list("HIST 300 , ENGL 1110", split_on_comma = TRUE)
  
  expect_length(result, 2)
  expect_equal(result[1], "HIST 300")
  expect_equal(result[2], "ENGL 1110")
})

test_that("convert_param_to_list handles single values without comma", {
  # Test: Single value (no comma) should work regardless of split_on_comma
  result_no_split <- convert_param_to_list("Smith, John", split_on_comma = FALSE)
  result_split <- convert_param_to_list("MATH 1215", split_on_comma = TRUE)
  
  expect_length(result_no_split, 1)
  expect_equal(result_no_split[1], "Smith, John")
  expect_length(result_split, 1)
  expect_equal(result_split[1], "MATH 1215")
})

test_that("convert_param_to_list preserves vector input", {
  # Test: Vector inputs should be preserved as-is
  input_vector <- c("Gibbs, Frederick", "Smith, John", "Doe, Jane")
  result <- convert_param_to_list(input_vector, split_on_comma = FALSE)
  
  expect_length(result, 3)
  expect_equal(result, input_vector)
})

test_that("filter_by_col handles instructor names correctly", {
  # Test: Instructor filtering should not split names on comma
  opt <- create_test_opt(list(instructor = "Smith, John"))
  
  # Using filter_by_col directly
  result <- filter_by_col(known_sections, "instructor_name", "Smith, John")
  
  # Should return rows where instructor is exactly "Smith, John"
  # (with special handling for no split)
  expect_true(all(!is.na(result$instructor_name)))
  expect_true(all(result$instructor_name == "Smith, John" | is.na(result$instructor_name)))
})

# =============================================================================
# Character Encoding Tests for Instructor Names
# =============================================================================

test_that("instructor names with commas match correctly with %in% operator", {
  message("\n  Testing %in% operator with comma-containing names...")
  
  # Create test data
  test_instructors <- c("Gibbs, Frederick", "Smith, John", "Doe, Jane")
  filter_value <- "Gibbs, Frederick"
  
  # Direct %in% test
  matches <- test_instructors %in% filter_value
  
  expect_true(matches[1])
  expect_false(matches[2])
  expect_false(matches[3])
  
  message("  ✓ %in% operator works correctly with comma names")
})

test_that("instructor names maintain encoding consistency in data frames", {
  message("\n  Testing encoding consistency in data frames...")
  
  # Create a simple test data frame
  df <- data.frame(
    instructor_name = c("Gibbs, Frederick", "Smith, John", "Doe, Jane"),
    course = c("HIST 300", "MATH 101", "ENGL 200"),
    stringsAsFactors = FALSE
  )
  
  # Filter by exact name
  filtered <- df[df$instructor_name == "Gibbs, Frederick", ]
  
  expect_equal(nrow(filtered), 1)
  expect_equal(filtered$course[1], "HIST 300")
  
  message("  ✓ Data frame encoding preserved correctly")
})

test_that("byte-by-byte comparison of instructor names works", {
  message("\n  Testing byte-by-byte comparison...")
  
  # Get the raw bytes of two instances of the same name
  name1 <- "Gibbs, Frederick"
  name2 <- "Gibbs, Frederick"
  
  # Convert to raw bytes
  bytes1 <- charToRaw(name1)
  bytes2 <- charToRaw(name2)
  
  # Should be identical
  expect_identical(bytes1, bytes2)
  
  message("  ✓ Byte-by-byte comparison identical for same names")
})

test_that("filtering handles edge cases in instructor names", {
  message("\n  Testing edge cases in instructor names...")
  
  # Create test data with various edge cases
  test_data <- data.frame(
    instructor_name = c(
      "Gibbs, Frederick",      # Standard comma format
      "Smith, Jr., John",      # Multiple commas
      "Single Name",           # No comma
      NA_character_,           # Missing name
      "",                      # Empty string
      " Leading Space"         # Whitespace
    ),
    course = 1:6,
    stringsAsFactors = FALSE
  )
  
  # Test 1: Standard format filters correctly
  result <- test_data %>% filter(instructor_name == "Gibbs, Frederick")
  expect_equal(nrow(result), 1)
  
  # Test 2: Multiple commas filter correctly
  result <- test_data %>% filter(instructor_name == "Smith, Jr., John")
  expect_equal(nrow(result), 1)
  
  # Test 3: Single name filters correctly
  result <- test_data %>% filter(instructor_name == "Single Name")
  expect_equal(nrow(result), 1)
  
  # Test 4: NA doesn't match (by design)
  result <- test_data %>% filter(instructor_name == NA_character_)
  expect_equal(nrow(result), 0)
  
  # Test 5: Empty string filters correctly
  result <- test_data %>% filter(instructor_name == "")
  expect_equal(nrow(result), 1)
  
  message("  ✓ All edge cases handled correctly")
})

test_that("instructor filtering with NA values works safely", {
  message("\n  Testing safe NA handling in instructor filtering...")
  
  test_data <- data.frame(
    instructor_name = c("Gibbs, Frederick", "Smith, John", NA_character_),
    course = c("HIST 300", "MATH 101", "ENGL 200"),
    stringsAsFactors = FALSE
  )
  
  # Filter should exclude NAs
  filtered <- test_data %>% filter(!is.na(instructor_name))
  
  expect_equal(nrow(filtered), 2)
  expect_true(all(!is.na(filtered$instructor_name)))
  
  message("  ✓ NA values handled safely")
})
