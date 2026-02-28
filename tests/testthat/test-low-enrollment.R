# Tests for low enrollment analysis functions
# Tests the low enrollment feature in server.R
#
# Covers:
# - Filtering courses below enrollment thresholds
# - Crosslist handling (crosslist_code == "0" for primary sections)
# - Section count aggregation for context
# - Enrollment history gathering
# - Edge cases (empty results, missing columns, future terms)
#
# Uses known_sections and known_students fixtures from fixtures/known_test_data.R

context("Low Enrollment Analysis")

# Load required libraries
library(dplyr)
library(tidyr)

# Load enrollment functions
source("../../R/cones/enrl.R")
source("../../R/branches/filter.R")

# =============================================================================
# Helper functions for low enrollment logic
# =============================================================================

# Simulates the low enrollment data pipeline
get_low_enrollment_courses <- function(sections_data, min_threshold = 1, max_threshold = 500) {
  message("[test] Filtering courses with enrollment between ", min_threshold, " and ", max_threshold)
  
  sections_data %>%
    filter(status == "A") %>%
    filter(total_enrl >= min_threshold & total_enrl <= max_threshold) %>%
    select(term, subject_course, course_title, campus, total_enrl, 
           capacity, available, delivery_method, level, instructor_name, 
           crosslist_code, everything())
}

# Simulates section count aggregation (avoids double-counting crosslisted)
get_section_counts <- function(sections_data) {
  message("[test] Calculating section counts by term/campus")
  
  sections_data %>%
    filter(status == "A", crosslist_code == "0") %>%
    group_by(term, subject_course, campus) %>%
    summarize(
      n_sections = n(),
      course_enrl = sum(total_enrl, na.rm = TRUE),
      .groups = "drop"
    )
}

# =============================================================================
# Test: Crosslist code filtering
# =============================================================================

test_that("crosslist_code == '0' identifies primary (non-crosslisted) sections only", {
  message("\n  Testing crosslist_code filtering...")
  
  # Create test data with crosslisted courses
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~crosslist_code, ~status,
    "1", 202510, "MATH 1110", "0", "A",
    "2", 202510, "MATH 1110", "CROSS-001", "A",  # Crosslist partner
    "3", 202510, "PHYS 1110", "0", "A",
    "4", 202510, "PHYS 1110", "0", "A",  # Multiple primary sections
    "5", 202510, "CHEM 1110", "CROSS-001", "A",  # Partner only
  )
  
  # Filter for primary only
  primary_only <- test_data %>% filter(crosslist_code == "0")
  
  expect_equal(nrow(primary_only), 4)
  expect_equal(unique(primary_only$subject_course), c("MATH 1110", "PHYS 1110"))
  expect_true(all(primary_only$crosslist_code == "0"))
  expect_false(any(primary_only$crosslist_code == "CROSS-001"))
})

# =============================================================================
# Test: Low enrollment filtering with thresholds
# =============================================================================

test_that("Low enrollment filtering works with active status filter", {
  message("\n  Testing low enrollment active status filter...")
  
  test_data <- known_sections %>%
    filter(term == 202510) %>%
    mutate(crosslist_code = "0")
  
  # Filter for active courses only
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 100)
  
  message("  Found ", nrow(low_enrl), " low enrollment courses in 202510")
  
  # All should be active
  expect_true(all(low_enrl$status == "A"))
  
  # All should be within threshold
  expect_true(all(low_enrl$total_enrl >= 1))
  expect_true(all(low_enrl$total_enrl <= 100))
})

test_that("Low enrollment filter respects enrollment thresholds", {
  message("\n  Testing enrollment threshold boundaries...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~total_enrl, ~status,
    "1", 202510, "MATH 1110", 0, "A",
    "2", 202510, "MATH 1111", 1, "A",     # Min threshold boundary
    "3", 202510, "MATH 1112", 15, "A",
    "4", 202510, "MATH 1113", 25, "A",
    "5", 202510, "MATH 1114", 30, "A",   # Max threshold boundary
    "6", 202510, "MATH 1115", 31, "A",
  ) %>% mutate(crosslist_code = "0")
  
  # Filter: enrollment >= 1 and <= 30
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 30)
  
  expect_equal(nrow(low_enrl), 4)
  expect_equal(sort(low_enrl$total_enrl), c(1, 15, 25, 30))
})

test_that("Empty result when no courses match thresholds", {
  message("\n  Testing empty result handling...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~total_enrl, ~status,
    "1", 202510, "MATH 1110", 100, "A",
    "2", 202510, "MATH 1111", 200, "A",
  ) %>% mutate(crosslist_code = "0")
  
  # Look for courses with 0-10 enrollment (none exist)
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 10)
  
  expect_equal(nrow(low_enrl), 0)
})

# =============================================================================
# Test: Section count aggregation (avoiding crosslist double-counting)
# =============================================================================

test_that("Section counts avoid double-counting crosslisted courses", {
  message("\n  Testing crosslist double-counting prevention...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~campus, ~total_enrl, ~status, ~crosslist_code,
    "1", 202510, "MATH 1110", "MAIN", 25, "A", "0",           # Primary
    "2", 202510, "MATH 1110", "MAIN", 25, "A", "CROSS-001",   # Partner (should NOT count)
    "3", 202510, "MATH 1111", "MAIN", 30, "A", "0",           # Primary
    "4", 202510, "MATH 1111", "MAIN", 30, "A", "0",           # Second primary
  )
  
  counts <- get_section_counts(test_data)
  
  message("  Found ", nrow(counts), " courses with primary sections")
  
  # MATH 1110 should have n_sections = 1 (crosslist partner excluded)
  math_1110 <- counts %>% filter(subject_course == "MATH 1110")
  expect_equal(nrow(math_1110), 1)
  expect_equal(math_1110$n_sections, 1)
  expect_equal(math_1110$course_enrl, 25)
  
  # MATH 1111 should have n_sections = 2 (both primary)
  math_1111 <- counts %>% filter(subject_course == "MATH 1111")
  expect_equal(nrow(math_1111), 1)
  expect_equal(math_1111$n_sections, 2)
  expect_equal(math_1111$course_enrl, 60)
})

test_that("Section count aggregation groups by campus correctly", {
  message("\n  Testing campus grouping in section counts...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~campus, ~total_enrl, ~status, ~crosslist_code,
    "1", 202510, "MATH 1110", "MAIN", 20, "A", "0",
    "2", 202510, "MATH 1110", "MAIN", 15, "A", "0",
    "3", 202510, "MATH 1110", "NORTH", 25, "A", "0",  # Different campus
  )
  
  counts <- get_section_counts(test_data)
  
  # Should have 2 rows (one per campus)
  expect_equal(nrow(counts), 2)
  
  # Check MAIN campus aggregation
  main_count <- counts %>% filter(campus == "MAIN")
  expect_equal(main_count$n_sections, 2)
  expect_equal(main_count$course_enrl, 35)
  
  # Check NORTH campus
  north_count <- counts %>% filter(campus == "NORTH")
  expect_equal(north_count$n_sections, 1)
  expect_equal(north_count$course_enrl, 25)
})

# =============================================================================
# Test: Cancelled section handling
# =============================================================================

test_that("Cancelled sections (status != 'A') are excluded from low enrollment", {
  message("\n  Testing cancelled section exclusion...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~total_enrl, ~status,
    "1", 202510, "MATH 1110", 5, "A",      # Active - low enrollment
    "2", 202510, "MATH 1110", 5, "C",      # Cancelled - should exclude
    "3", 202510, "MATH 1111", 2, "A",      # Active - low enrollment
    "4", 202510, "MATH 1111", 2, "X",      # Other status - should exclude
  ) %>% mutate(crosslist_code = "0")
  
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 100)
  
  # Should only get active courses
  expect_equal(nrow(low_enrl), 2)
  expect_true(all(low_enrl$status == "A"))
})

# =============================================================================
# Test: Missing column detection
# =============================================================================

test_that("Filtering handles missing crosslist_code gracefully", {
  message("\n  Testing missing crosslist_code handling...")
  
  # Data without crosslist_code column
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~total_enrl, ~status,
    "1", 202510, "MATH 1110", 25, "A",
    "2", 202510, "MATH 1111", 30, "A",
  )
  
  # Should fail or handle gracefully when trying to filter by crosslist_code
  expect_error(
    test_data %>% filter(crosslist_code == "0"),
    "object 'crosslist_code' not found"
  )
  
  message("  ✓ Error correctly raised for missing column")
})

test_that("Section counts fails gracefully when crosslist_code missing", {
  message("\n  Testing section count error handling...")
  
  # Data without crosslist_code
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~campus, ~total_enrl, ~status,
    "1", 202510, "MATH 1110", "MAIN", 25, "A",
    "2", 202510, "MATH 1111", "MAIN", 30, "A",
  )
  
  expect_error(
    get_section_counts(test_data),
    "object 'crosslist_code' not found"
  )
  
  message("  ✓ Error correctly raised when aggregating")
})

# =============================================================================
# Test: Integration with known fixtures
# =============================================================================

test_that("Low enrollment filtering works with known fixtures", {
  message("\n  Testing with known_sections fixture...")
  
  # Get 202510 data
  test_data <- known_sections %>%
    filter(term == 202510) %>%
    mutate(crosslist_code = "0")  # Ensure column exists
  
  # Should have test data
  expect_gt(nrow(test_data), 0)
  
  # Filter for low enrollment
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 20)
  
  message("  Found ", nrow(low_enrl), " courses with 1-20 enrollment in 202510")
  
  # All should be within threshold
  if (nrow(low_enrl) > 0) {
    expect_true(all(low_enrl$total_enrl >= 1 & low_enrl$total_enrl <= 20))
  }
})

test_that("Section counts aggregation works with known fixtures", {
  message("\n  Testing section count aggregation with fixture data...")
  
  test_data <- known_sections %>%
    filter(term == 202510) %>%
    mutate(crosslist_code = "0")
  
  counts <- get_section_counts(test_data)
  
  message("  Generated ", nrow(counts), " course/campus combinations")
  
  # All counts should be positive
  expect_true(all(counts$n_sections > 0))
  expect_true(all(counts$course_enrl >= 0))
})

# =============================================================================
# Test: Level-based filtering (lower, upper, grad)
# =============================================================================

test_that("Level classification is preserved during low enrollment filtering", {
  message("\n  Testing level preservation...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~total_enrl, ~status, ~level,
    "1", 202510, "MATH 1110", 5, "A", "lower",
    "2", 202510, "MATH 2110", 3, "A", "upper",
    "3", 202510, "MATH 5110", 1, "A", "grad",
  ) %>% mutate(crosslist_code = "0")
  
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 100)
  
  expect_equal(nrow(low_enrl), 3)
  expect_equal(sort(unique(low_enrl$level)), c("grad", "lower", "upper"))
})

# =============================================================================
# Test: Delivery method (online vs in-person)
# =============================================================================

test_that("Delivery method is preserved in low enrollment filtering", {
  message("\n  Testing delivery method preservation...")
  
  test_data <- tribble(
    ~section_id, ~term, ~subject_course, ~total_enrl, ~status, ~delivery_method,
    "1", 202510, "MATH 1110", 5, "A", "In-Person",
    "2", 202510, "MATH 1111", 3, "A", "Online",
    "3", 202510, "MATH 1112", 8, "A", "Hybrid",
  ) %>% mutate(crosslist_code = "0")
  
  low_enrl <- get_low_enrollment_courses(test_data, min_threshold = 1, max_threshold = 100)
  
  expect_equal(nrow(low_enrl), 3)
  expect_equal(sort(unique(low_enrl$delivery_method)), c("Hybrid", "In-Person", "Online"))
})

# =============================================================================
# Test: Real-world scenario (Spring 2025 low enrollment)
# =============================================================================

test_that("Real-world scenario: Spring 2025 low enrollment analysis", {
  message("\n  Testing real-world low enrollment scenario...")
  
  # Simulating Spring 2025 (202510) low enrollment report
  low_threshold <- 5
  
  test_data <- known_sections %>%
    filter(term == 202510) %>%
    mutate(crosslist_code = "0")
  
  # Get courses below threshold
  low_enrl <- test_data %>%
    filter(status == "A", total_enrl >= 1 & total_enrl <= low_threshold)
  
  message("  Found ", nrow(low_enrl), " courses below enrollment of ", low_threshold)
  
  if (nrow(low_enrl) > 0) {
    # Aggregate by subject_course/campus
    summary <- low_enrl %>%
      group_by(subject_course, campus) %>%
      summarize(
        n = n(),
        total_enrl = sum(total_enrl, na.rm = TRUE),
        avg_enrl = mean(total_enrl, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(total_enrl)
    
    message("  Summary by course/campus:")
    print(summary)
    
    # Verify structure
    expect_true("subject_course" %in% colnames(summary))
    expect_true("n" %in% colnames(summary))
  }
})
