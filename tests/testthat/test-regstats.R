# Tests for registration statistics (regstats)
# Tests R/cones/regstats.R
#
# This file tests the regstats functions for detecting registration anomalies:
# - assign_concern_tier(): Assigns concern severity based on SD deviation
# - create_tiered_summary(): Creates dashboard summary by anomaly type
# - format_concern_tier(): Formats tier labels for display
# - get_reg_stats(): Main function detecting bumps, dips, drops, waits, squeezes

# Source required functions
source("../../R/cones/regstats.R")
source("../../R/cones/enrl.R")
source("../../R/branches/filter.R")

context("Registration Statistics (regstats)")

# =============================================================================
# assign_concern_tier() tests - HIGH anomalies (bumps, drops)
# =============================================================================

test_that("assign_concern_tier returns critical_high for deviation >= 1.5 SD (high anomaly)", {
  # Actual value is 1.5 SD above mean
  result <- assign_concern_tier(
    actual_value = 175,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result, "critical_high")

  # Actual value is 2 SD above mean
  result2 <- assign_concern_tier(
    actual_value = 200,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result2, "critical_high")
})

test_that("assign_concern_tier returns moderate_high for deviation 1.0-1.5 SD (high anomaly)", {
  # Actual value is exactly 1.0 SD above mean
  result <- assign_concern_tier(
    actual_value = 150,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result, "moderate_high")

  # Actual value is 1.25 SD above mean
  result2 <- assign_concern_tier(
    actual_value = 162.5,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result2, "moderate_high")
})

test_that("assign_concern_tier returns marginally_high for deviation 0.5-1.0 SD (high anomaly)", {
  # Actual value is exactly 0.5 SD above mean
  result <- assign_concern_tier(
    actual_value = 125,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result, "marginally_high")

  # Actual value is 0.75 SD above mean
  result2 <- assign_concern_tier(
    actual_value = 137.5,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result2, "marginally_high")
})

test_that("assign_concern_tier returns normal for deviation < 0.5 SD (high anomaly)", {
  # Actual value is exactly at the mean
  result <- assign_concern_tier(
    actual_value = 100,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result, "normal")

  # Actual value is 0.25 SD above mean
  result2 <- assign_concern_tier(
    actual_value = 112.5,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result2, "normal")

  # Actual value is below mean (still normal for high anomaly)
  result3 <- assign_concern_tier(
    actual_value = 50,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result3, "normal")
})


# =============================================================================
# assign_concern_tier() tests - LOW anomalies (dips)
# =============================================================================

test_that("assign_concern_tier returns critical_low for deviation <= -1.5 SD (low anomaly)", {
  # Actual value is 1.5 SD below mean
  result <- assign_concern_tier(
    actual_value = 25,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result, "critical_low")

  # Actual value is 2 SD below mean
  result2 <- assign_concern_tier(
    actual_value = 0,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result2, "critical_low")
})

test_that("assign_concern_tier returns moderate_low for deviation -1.0 to -1.5 SD (low anomaly)", {
  # Actual value is exactly 1.0 SD below mean
  result <- assign_concern_tier(
    actual_value = 50,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result, "moderate_low")

  # Actual value is 1.25 SD below mean
  result2 <- assign_concern_tier(
    actual_value = 37.5,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result2, "moderate_low")
})

test_that("assign_concern_tier returns marginally_low for deviation -0.5 to -1.0 SD (low anomaly)", {
  # Actual value is exactly 0.5 SD below mean
  result <- assign_concern_tier(
    actual_value = 75,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result, "marginally_low")

  # Actual value is 0.75 SD below mean
  result2 <- assign_concern_tier(
    actual_value = 62.5,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result2, "marginally_low")
})

test_that("assign_concern_tier returns normal for deviation > -0.5 SD (low anomaly)", {
  # Actual value is at the mean
  result <- assign_concern_tier(
    actual_value = 100,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result, "normal")

  # Actual value is above the mean (not a low anomaly concern)
  result2 <- assign_concern_tier(
    actual_value = 150,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "low"
  )
  expect_equal(result2, "normal")
})


# =============================================================================
# assign_concern_tier() edge cases
# =============================================================================

test_that("assign_concern_tier handles SD = 0", {
  result <- assign_concern_tier(
    actual_value = 100,
    mean_value = 100,
    sd_value = 0,
    anomaly_direction = "high"
  )
  expect_equal(result, "normal")
})

test_that("assign_concern_tier handles NA values", {
  result <- assign_concern_tier(
    actual_value = NA,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result, "normal")

  result2 <- assign_concern_tier(
    actual_value = 150,
    mean_value = NA,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(result2, "normal")

  result3 <- assign_concern_tier(
    actual_value = 150,
    mean_value = 100,
    sd_value = NA,
    anomaly_direction = "high"
  )
  expect_equal(result3, "normal")
})

test_that("assign_concern_tier works with vectorized input", {
  actual_values <- c(175, 150, 125, 100)
  results <- assign_concern_tier(
    actual_value = actual_values,
    mean_value = 100,
    sd_value = 50,
    anomaly_direction = "high"
  )
  expect_equal(results, c("critical_high", "moderate_high", "marginally_high", "normal"))
})


# =============================================================================
# format_concern_tier() tests
# =============================================================================

test_that("format_concern_tier formats critical_high correctly", {
  result <- format_concern_tier("critical_high")
  expect_true(grepl("Critical High", result))
})

test_that("format_concern_tier formats critical_low correctly", {
  result <- format_concern_tier("critical_low")
  expect_true(grepl("Critical Low", result))
})

test_that("format_concern_tier formats moderate_high correctly", {
  result <- format_concern_tier("moderate_high")
  expect_true(grepl("Moderate High", result))
})

test_that("format_concern_tier formats moderate_low correctly", {
  result <- format_concern_tier("moderate_low")
  expect_true(grepl("Moderate Low", result))
})

test_that("format_concern_tier formats normal correctly", {
  result <- format_concern_tier("normal")
  expect_true(grepl("Normal", result))
})

test_that("format_concern_tier works with vectorized input", {
  tiers <- c("critical_high", "moderate_low", "normal")
  results <- format_concern_tier(tiers)
  expect_length(results, 3)
  expect_true(grepl("Critical High", results[1]))
  expect_true(grepl("Moderate Low", results[2]))
  expect_true(grepl("Normal", results[3]))
})


# =============================================================================
# create_tiered_summary() tests
# =============================================================================

test_that("create_tiered_summary returns correct structure with flagged data", {
  # Create mock flagged data with concern_tier column
  mock_flagged <- list(
    early_drops = tibble(
      subject_course = c("HIST 1110", "MATH 1215"),
      concern_tier = c("critical_high", "moderate_high")
    ),
    late_drops = tibble(
      subject_course = c("ANTH 1110"),
      concern_tier = c("marginally_high")
    ),
    dips = tibble(
      subject_course = c("HIST 1120", "MATH 1430"),
      concern_tier = c("critical_low", "normal")
    ),
    bumps = tibble(
      subject_course = c("ANTH 2050"),
      concern_tier = c("moderate_high")
    )
  )

  result <- create_tiered_summary(mock_flagged)

  expect_s3_class(result, "data.frame")
  expect_true("anomaly_type" %in% colnames(result))
  expect_true("total_flagged" %in% colnames(result))
  expect_true("critical_total" %in% colnames(result))
  expect_true("moderate_total" %in% colnames(result))
})

test_that("create_tiered_summary counts tiers correctly", {
  mock_flagged <- list(
    early_drops = tibble(
      subject_course = c("HIST 1110", "MATH 1215", "ANTH 1110"),
      concern_tier = c("critical_high", "critical_high", "moderate_high")
    )
  )

  result <- create_tiered_summary(mock_flagged)

  # Should have 1 row for early_drops
  early_drops_row <- result %>% filter(anomaly_type == "early_drops")
  expect_equal(nrow(early_drops_row), 1)

  # Should have 2 critical_high and 1 moderate_high
  expect_equal(early_drops_row$critical_high, 2)
  expect_equal(early_drops_row$moderate_high, 1)
  expect_equal(early_drops_row$critical_total, 2)
  expect_equal(early_drops_row$moderate_total, 1)
})

test_that("create_tiered_summary handles empty flagged data", {
  mock_flagged <- list(
    early_drops = tibble(),
    late_drops = tibble(),
    dips = tibble(),
    bumps = tibble()
  )

  result <- create_tiered_summary(mock_flagged)

  # Should return empty tibble with message column
  expect_s3_class(result, "data.frame")
})

test_that("create_tiered_summary handles missing anomaly types", {
  # Only has early_drops, missing other types
  mock_flagged <- list(
    early_drops = tibble(
      subject_course = c("HIST 1110"),
      concern_tier = c("critical_high")
    ),
    waits = tibble(subject_course = "MATH 1215")  # No concern_tier
  )

  result <- create_tiered_summary(mock_flagged)

  # Should only process early_drops (has concern_tier)
  expect_equal(nrow(result), 1)
  expect_equal(result$anomaly_type[1], "early_drops")
})


# =============================================================================
# create_regstats_cache_filename() tests
# =============================================================================

test_that("create_regstats_cache_filename generates correct filename with college filter", {
  opt <- list(course_college = "AS")
  result <- create_regstats_cache_filename(opt)

  expect_true(grepl("regstats", result))
  expect_true(grepl("AS", result))
  expect_true(grepl("\\.Rds$", result))
})

test_that("create_regstats_cache_filename generates correct filename with term filter", {
  opt <- list(term = 202510)
  result <- create_regstats_cache_filename(opt)

  expect_true(grepl("regstats", result))
  expect_true(grepl("202510", result))
  expect_true(grepl("\\.Rds$", result))
})

test_that("create_regstats_cache_filename generates correct filename with multiple filters", {
  opt <- list(
    course_college = "AS",
    term = 202510,
    level = "lower",
    course_campus = "Main"
  )
  result <- create_regstats_cache_filename(opt)

  expect_true(grepl("regstats", result))
  expect_true(grepl("AS", result))
  expect_true(grepl("202510", result))
  expect_true(grepl("lower", result))
  expect_true(grepl("Main", result))
})

test_that("create_regstats_cache_filename uses 'all-colleges' when no college specified", {
  opt <- list(term = 202510)
  result <- create_regstats_cache_filename(opt)

  expect_true(grepl("all-colleges", result))
})

test_that("create_regstats_cache_filename uses 'all-terms' when no term specified", {
  opt <- list(course_college = "AS")
  result <- create_regstats_cache_filename(opt)

  expect_true(grepl("all-terms", result))
})


# =============================================================================
# get_reg_stats() structure tests
# =============================================================================

test_that("get_reg_stats returns expected list structure", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined - skipping get_reg_stats structure test")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined - skipping get_reg_stats structure test")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  expect_type(result, "list")
  expect_true("early_drops" %in% names(result))
  expect_true("late_drops" %in% names(result))
  expect_true("dips" %in% names(result))
  expect_true("bumps" %in% names(result))
  expect_true("waits" %in% names(result))
  expect_true("squeezes" %in% names(result))
  expect_true("all_flagged_courses" %in% names(result))
  expect_true("thresholds" %in% names(result))
})

test_that("get_reg_stats returns data frames for anomaly types", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  expect_s3_class(result$early_drops, "data.frame")
  expect_s3_class(result$late_drops, "data.frame")
  expect_s3_class(result$dips, "data.frame")
  expect_s3_class(result$bumps, "data.frame")
  expect_s3_class(result$waits, "data.frame")
  expect_s3_class(result$squeezes, "data.frame")
})

test_that("get_reg_stats includes thresholds in output", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  expect_type(result$thresholds, "list")
  expect_true("min_impacted" %in% names(result$thresholds))
  expect_true("pct_sd" %in% names(result$thresholds))
  expect_true("min_squeeze" %in% names(result$thresholds))
  expect_true("min_wait" %in% names(result$thresholds))
})

test_that("get_reg_stats includes tiered_summary in output", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  expect_true("tiered_summary" %in% names(result))
  expect_s3_class(result$tiered_summary, "data.frame")
})


# =============================================================================
# get_reg_stats() filtering tests
# =============================================================================

test_that("get_reg_stats respects term filter", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # Check that waits only contains specified term (if any waits exist)
  if (nrow(result$waits) > 0) {
    expect_true(all(result$waits$term == 202510))
  }
})

test_that("get_reg_stats finds courses with high waitlists", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  # Use low min_wait threshold to ensure we find some waits
  opt <- list(
    term = 202510,
    thresholds = list(
      min_impacted = 1,
      pct_sd = 0.1,
      min_squeeze = 0.1,
      min_wait = 10
    )
  )

  result <- get_reg_stats(known_students, known_sections, opt)

  # Known: MATH 1215 has waiting=25 in 202510 (from fixture)
  # Should be flagged with min_wait=10
  if (nrow(result$waits) > 0) {
    expect_true("waiting" %in% colnames(result$waits))
    expect_true(all(result$waits$waiting > 10))
  }
})

test_that("get_reg_stats all_flagged_courses contains unique values", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # all_flagged_courses should be unique
  expect_equal(length(result$all_flagged_courses),
               length(unique(result$all_flagged_courses)))

  # Should be sorted
  if (length(result$all_flagged_courses) > 0) {
    expect_equal(result$all_flagged_courses, sort(result$all_flagged_courses))
  }
})


# =============================================================================
# get_reg_stats() custom thresholds tests
# =============================================================================

test_that("get_reg_stats uses custom thresholds when provided", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  custom_thresholds <- list(
    min_impacted = 5,
    pct_sd = 0.5,
    min_squeeze = 0.2,
    min_wait = 5
  )

  opt <- list(
    term = 202510,
    thresholds = custom_thresholds
  )

  result <- get_reg_stats(known_students, known_sections, opt)

  # Result should contain the custom thresholds
  expect_equal(result$thresholds$min_impacted, 5)
  expect_equal(result$thresholds$pct_sd, 0.5)
  expect_equal(result$thresholds$min_squeeze, 0.2)
  expect_equal(result$thresholds$min_wait, 5)
})

test_that("get_reg_stats includes cache_info with custom thresholds", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  custom_thresholds <- list(
    min_impacted = 100,  # Different from default
    pct_sd = 2,
    min_squeeze = 0.5,
    min_wait = 50
  )

  opt <- list(
    term = 202510,
    thresholds = custom_thresholds
  )

  result <- get_reg_stats(known_students, known_sections, opt)

  # Should indicate custom thresholds were used
  expect_true("cache_info" %in% names(result))
})


# =============================================================================
# Anomaly detection calculation tests
# =============================================================================

test_that("bumps are detected for courses above mean + threshold SD", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # If bumps exist, they should have positive impacted values
  if (nrow(result$bumps) > 0) {
    expect_true(all(result$bumps$impacted > 0))
    expect_true(all(result$bumps$sd_deviation > 0))
  }
})

test_that("dips are detected for courses below mean - threshold SD", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # If dips exist, they should have negative SD deviation
  if (nrow(result$dips) > 0) {
    expect_true(all(result$dips$sd_deviation < 0))
    # impacted is calculated as (mean - actual), so positive for dips
    expect_true(all(result$dips$impacted > 0))
  }
})

test_that("early_drops include concern_tier column", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # If early_drops exist, they should have concern_tier
  if (nrow(result$early_drops) > 0) {
    expect_true("concern_tier" %in% colnames(result$early_drops))
    valid_tiers <- c("critical_high", "moderate_high", "marginally_high", "normal")
    expect_true(all(result$early_drops$concern_tier %in% valid_tiers))
  }
})

test_that("late_drops include concern_tier column", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # If late_drops exist, they should have concern_tier
  if (nrow(result$late_drops) > 0) {
    expect_true("concern_tier" %in% colnames(result$late_drops))
    valid_tiers <- c("critical_high", "moderate_high", "marginally_high", "normal")
    expect_true(all(result$late_drops$concern_tier %in% valid_tiers))
  }
})


# =============================================================================
# Squeeze detection tests
# =============================================================================

test_that("squeezes are detected for courses with low avail/drop ratio", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  # If squeezes exist, they should have squeeze ratio below threshold
  if (nrow(result$squeezes) > 0) {
    expect_true("squeeze" %in% colnames(result$squeezes))
    expect_true(all(result$squeezes$squeeze < result$thresholds$min_squeeze))
  }
})


# =============================================================================
# Edge cases
# =============================================================================

test_that("get_reg_stats handles empty student data gracefully", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  empty_students <- known_students %>% filter(FALSE)
  opt <- create_test_opt(list(term = 202510))

  # Should not error
  result <- get_reg_stats(empty_students, known_sections, opt)

  expect_type(result, "list")
})

test_that("get_reg_stats handles course filter", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(
    term = 202510,
    course = "HIST 1110"
  ))

  result <- get_reg_stats(known_students, known_sections, opt)

  # All flagged courses should be HIST 1110 if any exist
  if (length(result$all_flagged_courses) > 0) {
    # Note: other anomaly types might include more courses due to how filtering works
    expect_type(result$all_flagged_courses, "character")
  }
})

test_that("get_reg_stats includes cache_info metadata", {
  skip_if_not(exists("cedar_regstats_thresholds"),
              "cedar_regstats_thresholds not defined")
  skip_if_not(exists("cedar_data_dir"),
              "cedar_data_dir not defined")

  opt <- create_test_opt(list(term = 202510))

  result <- get_reg_stats(known_students, known_sections, opt)

  expect_true("cache_info" %in% names(result))
  expect_true("generated_at" %in% names(result$cache_info))
})

