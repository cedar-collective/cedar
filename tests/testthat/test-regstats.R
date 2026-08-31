# Tests for registration statistics (regstats)
# Tests R/features/regstats.R
#
# This file tests the regstats functions for detecting registration anomalies:
# - assign_concern_tier(): Assigns concern severity based on SD deviation
# - create_tiered_summary(): Creates dashboard summary by anomaly type
# - format_concern_tier(): Formats tier labels for display
# - get_reg_stats(): Main function detecting bumps, dips, drops, waits, squeezes

context("Registration Statistics (regstats)")

regstats_history_opt <- function(term = 202080L) {
  list(term = term, bypass_cache = TRUE,
       thresholds = list(min_impacted = 1, pct_sd = 1, chronic_fill_rate = .60,
                         min_sat_terms = 1, min_wait = 1, section_proximity = .3))
}

test_that("Regstats uses earlier matching terms for every mean and population SD", {
  result <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt())
  focal <- function(df) df %>% filter(subject_course == "RSTA 100", campus == "ABQ", part_term == "1")
  bump <- focal(result$bumps)
  expect_equal(nrow(bump), 1L)
  expect_equal(bump$census_enrl_mean, 54)
  expect_equal(bump$pop_sd, 10)
  expect_equal(bump$impacted, 36)
  expect_equal(bump$sd_deviation, 4.6)
  expect_equal(bump$n_hist_terms, 2L)
  expect_equal(focal(result$early_drops)$dr_early_mean, 4)
  expect_equal(focal(result$early_drops)$pop_sd, 2)
  expect_equal(focal(result$early_drops)$impacted, 12)
  expect_equal(focal(result$late_drops)$dr_late_mean, 6)
  expect_equal(focal(result$late_drops)$pop_sd, 2)
  sat <- focal(result$sat)
  expect_equal(sat$fill_rate_mean, .54)
  expect_equal(sat$fill_rate_sd, .10)
  expect_equal(sat$sd_above_mean, 4.6)
  expect_equal(sat$n_hist_terms, 2L)
  expect_equal(sat$n_chronic_terms, 1L)
  expect_equal(result$bumps$census_enrl_mean[result$bumps$campus == "EA"], 7.5)
  expect_equal(result$bumps$census_enrl_mean[result$bumps$part_term == "1H"], 15)
  dip <- result$dips %>% filter(subject_course == "RSTA 101")
  expect_equal(dip$census_enrl_mean, 70)
  expect_equal(dip$pop_sd, 10)
  expect_equal(dip$impacted, 50)
})

test_that("later data cannot change past Regstats flags or baselines", {
  full <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt())
  past <- get_reg_stats(filter(test_students_regstats, term <= 202080L),
                       filter(test_sections_regstats, term <= 202080L), regstats_history_opt())
  for (name in c("bumps", "dips", "early_drops", "late_drops", "sat")) {
    # Full-series sparklines intentionally retain later context; the analytical
    # columns deciding an earlier flag must be identical without those terms.
    analytical <- function(df) df %>% ungroup() %>%
      select(-any_of(c("trend_hist", "trend_terms", "fill_hist", "fill_hist_terms"))) %>%
      arrange(campus, college, subject_course, part_term, term)
    expect_equal(analytical(full[[name]]), analytical(past[[name]]), info = name)
  }
})

test_that("multi-term Regstats gives each term its own earlier baseline", {
  combined <- get_reg_stats(test_students_regstats, test_sections_regstats,
                           regstats_history_opt(c(202080L, 202180L)))
  for (term_value in c(202080L, 202180L)) {
    single <- get_reg_stats(test_students_regstats, test_sections_regstats,
                           regstats_history_opt(term_value))
    for (name in c("bumps", "dips", "early_drops", "late_drops", "sat")) {
      expect_equal(filter(combined[[name]], term == term_value), single[[name]], info = name)
    }
  }
})

test_that("no, single-term, and flat histories do not generate SD flags", {
  result <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt())
  for (name in c("bumps", "dips", "early_drops", "late_drops", "running_hot_sat")) {
    expect_false(any(result[[name]]$subject_course %in% c("RSTA 102", "RSTA 103", "RSTA 104")))
    score <- if (name == "running_hot_sat") result[[name]]$sd_above_mean else result[[name]]$sd_deviation
    expect_true(all(is.finite(score)))
  }
  expect_equal(result$baseline_info$n_hist_terms, 2L)
  expect_equal(result$baseline_info$unscored,
               c(enrollment = 3, early_drops = 6, late_drops = 6, fill = 3))
  expect_match(result$baseline_info$coverage_note, "enrollment 3, early drops 6, late drops 6, fill 3")
})

test_that("precomputed enrollment and raw class lists give identical Regstats", {
  raw <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt())
  base <- calc_cl_enrls(test_students_regstats, by_part_term = TRUE)
  rlang::local_bindings(cedar_cl_enrls_base = base, .env = .GlobalEnv)
  cached_base <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt())
  expect_equal(cached_base[names(cached_base) != "cache_info"], raw[names(raw) != "cache_info"])
})

test_that("Regstats cache preserves baseline coverage and ignores unversioned results", {
  rlang::local_bindings(cedar_data_dir = withr::local_tempdir(), .env = .GlobalEnv)
  opt <- list(term = 202080L, bypass_cache = TRUE)
  fresh <- get_reg_stats(test_students_regstats, test_sections_regstats, opt)
  opt$bypass_cache <- FALSE
  loaded <- get_reg_stats(test_students_regstats, test_sections_regstats, opt)
  expect_true(loaded$cache_info$loaded_from_cache)
  expect_equal(loaded$summary, fresh$summary)
  expect_equal(loaded$baseline_info, fresh$baseline_info)
  filename <- create_regstats_cache_filename(opt)
  expect_match(filename, paste0("^regstats_v", cedar_regstats_cache_version, "_"))
  path <- file.path(cedar_data_dir, "regstats", filename)
  legacy <- sub(paste0("_v", cedar_regstats_cache_version), "", path, fixed = TRUE)
  expect_true(file.rename(path, legacy))
  expect_null(load_regstats_cache(opt))
})

test_that("Regstats trend tooltip reports the actual baseline separately from the full arc", {
  load_funcs(cedar_base_dir, modules = TRUE)
  html <- trend_cell_html(c(44, 64, 100, 10), c(201880L, 201980L, 202080L, 202180L),
                          202080L, baseline_mean = 54, baseline_n = 2L)
  expect_match(html, "prior avg 54.0 over 2 earlier terms", fixed = TRUE)
  expect_match(html, "full-arc:", fixed = TRUE)
})

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

test_that("create_regstats_cache_filename encodes part-of-term so PoT requests don't collide", {
  base_opt <- list(term = 202510, course_campus = "Main", dept_code = "MATH")
  base     <- create_regstats_cache_filename(base_opt)
  with_pt  <- create_regstats_cache_filename(c(base_opt, list(pt = "1H")))
  other_pt <- create_regstats_cache_filename(c(base_opt, list(pt = "2H")))

  # A PoT selection must change the cache key, and different PoTs must differ,
  # otherwise get_reg_stats() serves a stale cached result for the new PoT.
  expect_false(identical(base, with_pt))
  expect_false(identical(with_pt, other_pt))
  expect_true(grepl("pt1H", with_pt))
})


# =============================================================================
# get_reg_stats() structure tests
# =============================================================================

test_that("get_reg_stats returns expected list structure", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_type(result, "list")
  expect_true("early_drops"       %in% names(result))
  expect_true("late_drops"        %in% names(result))
  expect_true("dips"              %in% names(result))
  expect_true("bumps"             %in% names(result))
  expect_true("waits"             %in% names(result))
  expect_true("running_hot_sat"   %in% names(result))
  expect_true("chronic_sat"       %in% names(result))
  expect_true("all_flagged_courses" %in% names(result))
  expect_true("thresholds"        %in% names(result))
})

test_that("get_reg_stats returns data frames for anomaly types", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_s3_class(result$early_drops, "data.frame")
  expect_s3_class(result$late_drops,  "data.frame")
  expect_s3_class(result$dips,        "data.frame")
  expect_s3_class(result$bumps,       "data.frame")
  expect_s3_class(result$waits,       "data.frame")
  expect_s3_class(result$running_hot_sat, "data.frame")
  expect_s3_class(result$chronic_sat,  "data.frame")
})

test_that("get_reg_stats includes thresholds in output", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_type(result$thresholds, "list")
  expect_true("min_impacted" %in% names(result$thresholds))
  expect_true("pct_sd"       %in% names(result$thresholds))
  expect_true("chronic_fill_rate" %in% names(result$thresholds))
  expect_true("min_wait"     %in% names(result$thresholds))
})

test_that("dashboard threshold profile is more generous and cache-separated", {
  thresholds <- get_dashboard_regstats_thresholds(cedar_regstats_thresholds)

  expect_equal(thresholds$min_impacted, 5)
  expect_equal(thresholds$pct_sd, 0.5)
  expect_equal(thresholds$chronic_fill_rate, 0.85)
  expect_equal(thresholds$min_wait, 2)
  expect_equal(thresholds$min_sat_terms, 2)

  standard_name <- create_regstats_cache_filename(list(term = 202010, dept_code = "HIST"))
  dashboard_name <- create_regstats_cache_filename(list(
    term = 202010,
    dept_code = "HIST",
    threshold_profile = "dashboard"
  ))

  expect_match(dashboard_name, "profile-dashboard")
  expect_false(identical(standard_name, dashboard_name))
})

test_that("get_reg_stats applies dashboard threshold profile", {
  opt <- create_test_opt(list(
    term = 202010,
    threshold_profile = "dashboard"
  ))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_equal(result$thresholds$min_impacted, 5)
  expect_equal(result$thresholds$pct_sd, 0.5)
  expect_equal(result$thresholds$min_wait, 2)
  expect_equal(result$cache_info$threshold_profile, "dashboard")
  expect_false(result$cache_info$using_standard_thresholds)
})

test_that("get_reg_stats includes tiered_summary in output", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_true("tiered_summary" %in% names(result))
  expect_s3_class(result$tiered_summary, "data.frame")
})


# =============================================================================
# get_reg_stats() filtering tests
# =============================================================================

test_that("get_reg_stats respects term filter — fixture has 0 waits for 202010", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_s3_class(result$waits, "data.frame")
  expect_equal(nrow(result$waits), 0)
})

test_that("get_reg_stats all_flagged_courses is sorted and unique", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  courses <- result$all_flagged_courses
  expect_type(courses, "character")
  expect_identical(courses, sort(unique(courses)))
})


# =============================================================================
# get_reg_stats() custom thresholds tests
# =============================================================================

test_that("get_reg_stats uses custom thresholds when provided", {
  opt <- list(
    term = 202010,
    thresholds = list(
      min_impacted      = 5,
      pct_sd            = 0.5,
      chronic_fill_rate = 0.80,
      min_wait          = 5
    )
  )
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_equal(result$thresholds$min_impacted,      5)
  expect_equal(result$thresholds$pct_sd,            0.5)
  expect_equal(result$thresholds$chronic_fill_rate, 0.80)
  expect_equal(result$thresholds$min_wait,          5)
})

test_that("get_reg_stats includes cache_info with custom thresholds", {
  opt <- list(
    term = 202010,
    thresholds = list(
      min_impacted      = 100,
      pct_sd            = 2,
      chronic_fill_rate = 0.95,
      min_wait          = 50
    )
  )
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_true("cache_info" %in% names(result))
})


# =============================================================================
# Anomaly detection calculation tests
# =============================================================================

test_that("bumps: default min_impacted (20) flags no bumps for fixture 202010", {
  # This is the fixture's first spring. Later springs are not baseline evidence.
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_s3_class(result$bumps, "data.frame")
  expect_equal(nrow(result$bumps), 0)
})

test_that("lowering Min Impacted cannot turn future enrollment into baseline evidence", {
  # Previously ANTH 2175's first spring was flagged using the next spring's
  # smaller enrollment. A permissive threshold cannot make that history prior.
  # EC-11 above supplies positive bump cases with two actual earlier offerings.
  opt <- list(
    term         = 202010,
    bypass_cache = TRUE,
    thresholds   = list(
      min_impacted      = 10,
      pct_sd            = 1,
      chronic_fill_rate = 0.90,
      min_wait          = 20,
      section_proximity = 0.3
    )
  )
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_equal(nrow(result$bumps), 0)
  expect_equal(result$baseline_info$n_hist_terms, 0L)
  expect_gt(result$baseline_info$unscored[["enrollment"]], 0)
})

test_that("dips: fixture 202010 has 0 dips", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_s3_class(result$dips, "data.frame")
  expect_equal(nrow(result$dips), 0)
})

test_that("early_drops and late_drops: fixture 202010 has 0 of each", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_equal(nrow(result$early_drops), 0)
  expect_equal(nrow(result$late_drops),  0)
})


# =============================================================================
# Capacity saturation detection tests
# =============================================================================

test_that("running_hot_sat: result is a data frame with expected columns", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_s3_class(result$running_hot_sat, "data.frame")
  expect_true("fill_rate"      %in% colnames(result$running_hot_sat))
  expect_true("fill_rate_mean" %in% colnames(result$running_hot_sat))
  expect_true("sd_above_mean"  %in% colnames(result$running_hot_sat))
  # All flagged rows must exceed the pct_sd threshold
  if (nrow(result$running_hot_sat) > 0) {
    expect_true(all(result$running_hot_sat$sd_above_mean >= result$thresholds$pct_sd))
  }
})

test_that("chronic_sat: result is a data frame with expected columns", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_s3_class(result$chronic_sat, "data.frame")
  expect_true("fill_rate"       %in% colnames(result$chronic_sat))
  expect_true("n_chronic_terms" %in% colnames(result$chronic_sat))
  # All flagged rows must be at or above the chronic fill rate threshold
  if (nrow(result$chronic_sat) > 0) {
    expect_true(all(result$chronic_sat$fill_rate >= result$thresholds$chronic_fill_rate))
  }
})


# =============================================================================
# Edge cases
# =============================================================================

test_that("get_reg_stats handles empty student data gracefully", {
  empty_students <- test_students %>% filter(FALSE)
  opt            <- create_test_opt(list(term = 202010))

  result <- get_reg_stats(empty_students, test_sections, opt)

  expect_type(result, "list")
})

test_that("get_reg_stats handles course filter — returns character all_flagged_courses", {
  opt    <- create_test_opt(list(term = 202010, course = "HIST 1110"))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_type(result$all_flagged_courses, "character")
})

test_that("get_reg_stats includes cache_info metadata", {
  opt    <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt)

  expect_true("cache_info"    %in% names(result))
  expect_true("generated_at" %in% names(result$cache_info))
})
