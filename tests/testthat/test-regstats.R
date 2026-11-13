# Tests for registration statistics (regstats)
# Tests R/features/regstats.R
#
# This file tests the regstats functions for detecting registration anomalies:
# - assign_concern_tier(): Assigns concern severity based on SD deviation
# - create_tiered_summary(): Creates dashboard summary by anomaly type
# - format_concern_tier(): Formats tier labels for display
# - get_reg_stats(): Main function detecting bumps, dips, drops, waits, squeezes

context("Registration Statistics (regstats)")

test_that("Regstats uses earlier matching terms for every mean and population SD", {
  result <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                         course_terms = test_course_terms_regstats)
  focal <- function(df) df %>% filter(subject_course == "SOCI 100", campus == "ABQ", part_term == "1")
  bump <- focal(result$bumps)
  expect_equal(nrow(bump), 1L)
  expect_equal(bump$census_enrl_mean, 54)
  expect_equal(bump$pop_sd, 10)
  expect_equal(bump$impacted, 36)
  expect_equal(bump$sd_deviation, 4.6)
  expect_equal(bump$n_hist_terms, 2L)
  early <- focal(result$early_drops)
  expect_equal(early$dr_early_mean, 4)
  expect_equal(early$pop_sd, 2)
  expect_equal(early$impacted, 12)
  expect_equal(early$drop_denominator, 118)
  expect_equal(early$drop_rate, 18 / 118)
  expect_equal(early$drop_rate_mean, mean(c(2 / 46, 6 / 70)))
  expect_equal(early$drop_rate_change_pp,
               100 * (18 / 118 - mean(c(2 / 46, 6 / 70))))
  expect_equal(early$rate_hist_terms, 2L)
  late <- focal(result$late_drops)
  expect_equal(late$dr_late_mean, 6)
  expect_equal(late$pop_sd, 2)
  expect_equal(late$drop_denominator, 100)
  expect_equal(late$drop_rate, 20 / 100)
  expect_equal(late$drop_rate_mean, mean(c(4 / 44, 8 / 64)))
  expect_equal(late$drop_rate_change_pp,
               100 * (20 / 100 - mean(c(4 / 44, 8 / 64))))
  expect_equal(late$rate_hist_terms, 2L)
  sat <- focal(result$sat)
  expect_equal(sat$fill_rate_mean, .54)
  expect_equal(sat$fill_rate_sd, .10)
  expect_equal(sat$sd_above_mean, 4.6)
  expect_equal(sat$n_hist_terms, 2L)
  expect_equal(sat$n_chronic_terms, 1L)
  expect_equal(result$bumps$census_enrl_mean[result$bumps$campus == "EA"], 7.5)
  expect_equal(result$bumps$census_enrl_mean[result$bumps$part_term == "1H"], 15)
  dip <- result$dips %>% filter(subject_course == "SOCI 101")
  expect_equal(dip$census_enrl_mean, 70)
  expect_equal(dip$pop_sd, 10)
  expect_equal(dip$impacted, 50)
})

test_that("later data cannot change past Regstats flags or baselines", {
  full <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                         course_terms = test_course_terms_regstats)
  past_students <- filter(test_students_regstats, term <= 202080L)
  past_sections <- filter(test_sections_regstats, term <= 202080L)
  past <- get_reg_stats(past_students, past_sections, regstats_history_opt(),
                        course_terms = course_terms_for(past_students, past_sections))
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
                           regstats_history_opt(c(202080L, 202180L)), course_terms = test_course_terms_regstats)
  for (term_value in c(202080L, 202180L)) {
    single <- get_reg_stats(test_students_regstats, test_sections_regstats,
                           regstats_history_opt(term_value), course_terms = test_course_terms_regstats)
    for (name in c("bumps", "dips", "early_drops", "late_drops", "sat")) {
      expect_equal(filter(combined[[name]], term == term_value), single[[name]], info = name)
    }
  }
})

test_that("no, single-term, and flat histories do not generate SD flags", {
  result <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                         course_terms = test_course_terms_regstats)
  for (name in c("bumps", "dips", "early_drops", "late_drops", "running_hot_sat")) {
    expect_false(any(result[[name]]$subject_course %in% c("SOCI 102", "SOCI 103", "SOCI 104")))
    score <- if (name == "running_hot_sat") result[[name]]$sd_above_mean else result[[name]]$sd_deviation
    expect_true(all(is.finite(score)))
  }
  expect_equal(result$baseline_info$n_hist_terms, 2L)
  expect_equal(result$baseline_info$unscored,
               c(enrollment = 3, early_drops = 6, late_drops = 6, fill = 3))
  expect_match(result$baseline_info$coverage_note, "enrollment 3, early drops 6, late drops 6, fill 3")
  expect_match(result$baseline_info$coverage_note,
               "Saturation source coverage: .* matched class-list census to DESR capacity")
})

test_that("Regstats saturation uses class-list census rather than DESR snapshot enrollment", {
  base <- get_reg_stats(test_students_regstats, test_sections_regstats,
                        regstats_history_opt(), course_terms = test_course_terms_regstats)
  shifted_sections <- test_sections_regstats %>%
    mutate(
      .target = subject_course == "SOCI 100" & campus == "ABQ" &
        part_term == "1" & term == 202080L,
      enrolled = if_else(.target, enrolled - 15L, enrolled),
      total_enrl = if_else(.target, total_enrl - 15L, total_enrl),
      available = if_else(.target, available + 15L, available)
    ) %>%
    select(-.target)
  shifted <- get_reg_stats(test_students_regstats, shifted_sections, regstats_history_opt(),
                           course_terms = course_terms_for(test_students_regstats, shifted_sections))
  focal <- function(df) df %>%
    filter(subject_course == "SOCI 100", campus == "ABQ", part_term == "1")

  base_sat <- focal(base$sat)
  shifted_sat <- focal(shifted$sat)
  expect_equal(base_sat$fill_rate, 1)
  expect_equal(shifted_sat$fill_rate, base_sat$fill_rate)
  expect_equal(shifted_sat$census_enrl, 100)
  expect_equal(shifted_sat$desr_snapshot_fill, .65)
  expect_equal(shifted_sat$capacity, 100)
  expect_false(isTRUE(all.equal(
    shifted_sat$fill_rate,
    (shifted_sat$enrolled + shifted_sat$dr_late) / shifted_sat$capacity
  )))
})

test_that("Regstats definition v5 records the course key, lifecycle and waitlist source repairs", {
  definition <- cedar_definition("regstats")
  expect_identical(definition$version, "5.0.0")
  expect_match(definition$summary, "followed across the codes it has carried", fixed = TRUE)
  expect_match(definition$summary, "class-list census proxy", fixed = TRUE)
  expect_match(definition$summary, "drop-volume alerts remain count-based", fixed = TRUE)
  expect_match(definition$summary, "shared class-list true demand", fixed = TRUE)
  expect_match(definition$exclusions, "at least as large as Min Waiting", fixed = TRUE)
})

test_that("Regstats reads the course-term table, requires it, and refuses an option it cannot answer", {
  # The class list is no longer recounted (ADR-001 step 7): no table, no report.
  expect_error(get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt()),
               "course_terms")
  expect_error(get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                             course_terms = NULL), "course_terms")
  course_terms <- test_course_terms_regstats
  expect_true(course_terms_is_current(course_terms, test_students_regstats))
  expect_identical(attr(course_terms, "code_renames"), character(0))
  expect_identical(names(course_terms), COURSE_TERMS_COLUMNS)
  result <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                          course_terms = course_terms)

  # The table is a parameter, never a global (M12): a bogus table of the old
  # or new name in the global environment changes nothing.
  bogus <- course_terms %>% dplyr::mutate(registered = registered * 100L)
  rlang::local_bindings(cedar_course_terms = bogus, cedar_cl_enrls_base = bogus,
                        .env = .GlobalEnv)
  again <- get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                         course_terms = course_terms)
  expect_equal(again[names(again) != "cache_info"], result[names(result) != "cache_info"])

  # An option about one section or one student changes which rows count; the
  # table counts them all, so it is an error, never silently ignored.
  for (bad in list(list(inst = "Someone"), list(im = "ONL"), list(classification = "Freshman"))) {
    expect_error(
      get_reg_stats(test_students_regstats, test_sections_regstats,
                    c(regstats_history_opt(), bad), course_terms = course_terms),
      "does not carry", info = names(bad))
  }
})

test_that("Regstats refuses a course-term table not counted by this build over these codes", {
  # Counted by code, with no renames or build stamped on it: what global.R
  # saved before ADR-001 step 4, or before a code_history.csv row was confirmed.
  by_code <- calc_cl_enrls(test_students_regstats, by_part_term = TRUE)
  expect_false(course_terms_is_current(by_code, test_students_regstats))
  expect_error(
    get_reg_stats(test_students_regstats, test_sections_regstats, regstats_history_opt(),
                  course_terms = by_code),
    "build_course_terms"
  )
  # Saved by an older build, or short a column: rebuilt, never read.
  current <- test_course_terms_regstats
  older <- current
  attr(older, "course_terms_build_version") <- COURSE_TERMS_BUILD_VERSION - 1L
  expect_false(course_terms_is_current(older, test_students_regstats))
  expect_false(course_terms_is_current(dplyr::select(current, -census_enrl), test_students_regstats))
  # Counted over one class list's renames, it is not current for another's.
  rn <- rn01_course_tables()
  expect_false(course_terms_is_current(current, rn$cedar_registrations))
  rn_base <- course_terms_for(rn$cedar_registrations, rn$cedar_sections)
  expect_true(course_terms_is_current(rn_base, rn$cedar_registrations))
  # The class list already names the renamed subject (I45), so its renames
  # are the two renumberings; the schedule's SOC codes are on the sections.
  expect_identical(attr(rn_base, "code_renames"),
                   c("HIST 320 > HIST 3201", "SOCI 250 > SOCI 2315"))
  expect_true(all(rn_base$subject_course %in% c("HIST 3201", "LING 2110", "PHIL 150", "PHIL 1115",
                                                 "SOCI 2120", "SOCI 2315", "SOCI 371")))
  expect_false(course_terms_is_current(NULL, test_students_regstats))
})

test_that("Regstats stops on a table no loader attached", {
  expect_error(
    get_reg_stats(dplyr::select(test_students_regstats, -course_id), test_sections_regstats,
                  regstats_history_opt(), course_terms = test_course_terms_regstats),
    "course_id"
  )
})

test_that("Regstats follows a course across its codes (ADR-001 step 4)", {
  rn <- rn01_course_tables()
  # RN01 sections seat 20 and one student registers, so a 5% ceiling marks
  # every offering at cap; one prior term at cap is Chronically full here.
  rn_terms <- course_terms_for(rn$cedar_registrations, rn$cedar_sections)
  opt <- regstats_history_opt(term = 202110L)
  opt$thresholds$chronic_fill_rate <- 0.05
  result <- get_reg_stats(rn$cedar_registrations, rn$cedar_sections, opt, course_terms = rn_terms)

  # HIST 3201's Spring 2021 fill is compared with HIST 320's Spring 2020,
  # and the row says which code that history ran under.
  sat <- result$sat %>% dplyr::arrange(subject_course)
  expect_equal(sat$subject_course, c("HIST 3201", "LING 2110", "SOCI 2315"))
  hist <- sat %>% dplyr::filter(subject_course == "HIST 3201")
  expect_equal(hist$n_hist_terms, 1L)
  expect_equal(hist$n_chronic_terms, 1L)
  expect_true(hist$is_chronic_hist)
  expect_equal(hist$fill_hist_terms[[1]], c(202010L, 202110L))
  expect_equal(hist$former_codes, "HIST 320 (Spring 2020 to Fall 2020)")
  # The two-step chain: both earlier codes, each with its term.
  expect_equal(sat$former_codes[sat$subject_course == "SOCI 2315"],
               "SOC 250 (Spring 2020), SOCI 250 (Spring 2020)")
  # The control, offered twice under one code, names none.
  expect_true(is.na(sat$former_codes[sat$subject_course == "LING 2110"]))
  expect_false(any(c("HIST 320", "SOC 250", "SOCI 250") %in% result$all_flagged_courses))
  expect_equal(result$course_key_info$n_renamed_courses, 2L)
  expect_equal(result$course_key_info$renamed_courses, c("HIST 3201", "SOCI 2315"))
  expect_match(result$course_key_info$note, "2 flagged courses also ran under another code", fixed = TRUE)
  expect_identical(result$code_renames, course_code_renames(rn$cedar_registrations))
  # Every flagged table carries the column, flagged or empty.
  for (nm in c("bumps", "dips", "early_drops", "late_drops", "waits", "sat")) {
    expect_true("former_codes" %in% names(result[[nm]]), info = nm)
  }
  # The proposed renumbering assigns nothing: PHIL 150 and PHIL 1115 stay two
  # courses, and the Fall 2020 snapshot counts the schedule's courses by id.
  fall <- get_reg_stats(rn$cedar_registrations, rn$cedar_sections, regstats_history_opt(term = 202080L),
                        course_terms = rn_terms)
  expect_equal(fall$summary$lower$n_courses, 1L)
  expect_equal(fall$summary$upper$n_courses, 2L)
  expect_equal(fall$course_key_info$n_renamed_courses, 0L)
  expect_match(fall$course_key_info$note, "no flagged course ran under another code", fixed = TRUE)

  # A former code asked for is its course.
  former_opt <- opt
  former_opt$course <- "HIST 320"
  former <- get_reg_stats(rn$cedar_registrations, rn$cedar_sections, former_opt, course_terms = rn_terms)
  expect_equal(former$sat$subject_course, "HIST 3201")
  expect_equal(former$all_flagged_courses, "HIST 3201")
  expect_equal(former$sat$former_codes, "HIST 320 (Spring 2020 to Fall 2020)")
})

test_that("Regstats excludes a course the list names by a former code, on every path", {
  # Keyed on course_id, a list naming HIST 320 must drop the course HIST 3201
  # in every term, from the course-term table and the waits pass's class list
  # alike; matched by code, the table's HIST 3201 rows would survive and flag.
  rn <- rn01_course_tables()
  rn_terms <- course_terms_for(rn$cedar_registrations, rn$cedar_sections)
  expect_true("HIST 3201" %in% rn_terms$subject_course)
  opt <- regstats_history_opt(term = 202110L)
  opt$thresholds$chronic_fill_rate <- 0.05
  rlang::local_bindings(excluded_courses = "HIST 320", .env = .GlobalEnv)
  raw <- get_reg_stats(rn$cedar_registrations, rn$cedar_sections, opt, course_terms = rn_terms)
  expect_false("HIST 3201" %in% raw$all_flagged_courses)
  expect_equal(sort(raw$sat$subject_course), c("LING 2110", "SOCI 2315"))
  # HIST 3201 is Spring 2021's only upper-division course, so the snapshot
  # has no upper-division row once its course is excluded (1 by code).
  expect_null(raw$summary$upper$n_courses)
  expect_equal(raw$summary$lower$n_courses, 2L)
})

test_that("the schedule's old code joins the class list's new one in Regstats saturation (I45)", {
  rn <- rn01_course_tables()
  # Spring 2020: SOC 371 and SOC 250 are on the schedule, SOCI 371 and
  # SOCI 250 on the class list. By course every section finds its census.
  result <- get_reg_stats(rn$cedar_registrations, rn$cedar_sections, regstats_history_opt(term = 202010L),
                          course_terms = course_terms_for(rn$cedar_registrations, rn$cedar_sections))
  coverage <- result$baseline_info$saturation_coverage
  expect_equal(coverage$matched, 5L)
  expect_equal(coverage$unmatched, 0L)
  expect_match(result$baseline_info$coverage_note, "5 target groups matched", fixed = TRUE)
})

test_that("title enrichment cannot duplicate a Regstats reporting group", {
  title_source <- tibble::tibble(
    campus = "ABQ",
    college = "ARTS",
    subject_course = "SOCI 100",
    term = 202080L,
    part_term = c("1", "1", "1", "1H", "1H"),
    course_title = c("Survey", "Survey", "Special Topics", "Zulu", "Alpha")
  )
  reporting_rows <- tibble::tibble(
    campus = "ABQ",
    college = "ARTS",
    subject_course = "SOCI 100",
    term = 202080L,
    part_term = c("1", "1H"),
    impacted = c(12, 8)
  )
  flagged <- list(bumps = reporting_rows, waits = reporting_rows[1, ])

  enriched <- attach_regstats_titles(flagged, title_source)

  expect_equal(nrow(enriched$bumps), nrow(reporting_rows))
  expect_equal(nrow(enriched$waits), 1L)
  expect_equal(enriched$bumps$course_title, c("Survey", "Alpha"))
  expect_equal(
    nrow(dplyr::distinct(
      enriched$bumps, campus, college, subject_course, term, part_term
    )),
    nrow(enriched$bumps)
  )
})

test_that("Regstats cache preserves baseline coverage and ignores unversioned results", {
  rlang::local_bindings(cedar_data_dir = withr::local_tempdir(), .env = .GlobalEnv)
  opt <- list(term = 202080L, bypass_cache = TRUE)
  fresh <- get_reg_stats(test_students_regstats, test_sections_regstats, opt, course_terms = test_course_terms_regstats)
  opt$bypass_cache <- FALSE
  loaded <- get_reg_stats(test_students_regstats, test_sections_regstats, opt, course_terms = test_course_terms_regstats)
  expect_true(loaded$cache_info$loaded_from_cache)
  expect_equal(loaded$summary, fresh$summary)
  expect_equal(loaded$baseline_info, fresh$baseline_info)
  # A payload counted over other course codes is a miss.
  expect_identical(loaded$code_renames, character(0))
  expect_null(load_regstats_cache(opt, "SOC 371 > SOCI 371"))
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
# assign_concern_tier() boundaries and missing inputs
# =============================================================================

test_that("assign_concern_tier classifies high deviations at and between tier boundaries", {
  result <- assign_concern_tier(
    actual_value = c(175, 200, 150, 162.5, 125, 137.5, 100, 112.5, 50),
    mean_value = 100, sd_value = 50, anomaly_direction = "high"
  )
  expect_equal(result, c(
    "critical_high", "critical_high", "moderate_high", "moderate_high",
    "marginally_high", "marginally_high", "normal", "normal", "normal"
  ))
})


test_that("assign_concern_tier classifies low deviations at and between tier boundaries", {
  result <- assign_concern_tier(
    actual_value = c(25, 0, 50, 37.5, 75, 62.5, 100, 150),
    mean_value = 100, sd_value = 50, anomaly_direction = "low"
  )
  expect_equal(result, c(
    "critical_low", "critical_low", "moderate_low", "moderate_low",
    "marginally_low", "marginally_low", "normal", "normal"
  ))
})


test_that("assign_concern_tier leaves zero SD and missing inputs unflagged", {
  result <- assign_concern_tier(
    actual_value = c(100, NA, 150, 150),
    mean_value = c(100, 100, NA, 100),
    sd_value = c(0, 50, 50, NA),
    anomaly_direction = "high"
  )
  expect_equal(result, rep("normal", 4))
})


# =============================================================================
# format_concern_tier() tests
# =============================================================================

test_that("format_concern_tier labels high, low, and normal tiers in input order", {
  tiers <- c("critical_high", "critical_low", "moderate_high", "moderate_low", "normal")
  labels <- c("Critical High", "Critical Low", "Moderate High", "Moderate Low", "Normal")
  result <- format_concern_tier(tiers)

  expect_length(result, length(tiers))
  for (i in seq_along(tiers)) {
    expect_match(result[i], labels[i], fixed = TRUE)
  }
})


# =============================================================================
# create_tiered_summary() tests
# =============================================================================

test_that("create_tiered_summary counts severity across all anomaly types", {
  flagged <- list(
    early_drops = tibble(concern_tier = c("critical_high", "critical_high", "moderate_high")),
    late_drops = tibble(concern_tier = "marginally_high"),
    dips = tibble(concern_tier = c("critical_low", "normal")),
    bumps = tibble(concern_tier = "moderate_high")
  )
  result <- create_tiered_summary(flagged) %>% arrange(anomaly_type)

  expect_s3_class(result, "data.frame")
  expected <- tibble::tribble(
    ~anomaly_type, ~total_flagged, ~critical_total, ~moderate_total, ~marginal_total,
    "bumps",       1,              0,               1,               0,
    "dips",        2,              1,               0,               0,
    "early_drops", 3,              2,               1,               0,
    "late_drops",  1,              0,               0,               1
  )
  for (column in names(expected)) {
    expect_equal(result[[column]], expected[[column]], info = column)
  }
  early <- result %>% filter(anomaly_type == "early_drops")
  expect_equal(early$critical_high, 2)
  expect_equal(early$moderate_high, 1)
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

test_that("create_regstats_cache_filename encodes college and defaults to all terms", {
  result <- create_regstats_cache_filename(list(course_college = "AS"))

  expect_match(result, "regstats")
  expect_match(result, "AS")
  expect_match(result, "\\.Rds$")
  expect_match(result, "all-terms")
})

test_that("create_regstats_cache_filename encodes term and defaults to all colleges", {
  result <- create_regstats_cache_filename(list(term = 202510))

  expect_match(result, "regstats")
  expect_match(result, "202510")
  expect_match(result, "\\.Rds$")
  expect_match(result, "all-colleges")
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
# get_reg_stats() report contract and threshold profiles
# =============================================================================

test_that("get_reg_stats supplies the report contract and expected default fixture flags", {
  opt <- create_test_opt(list(term = 202010))
  result <- get_reg_stats(test_students, test_sections, opt, course_terms = test_course_terms)

  expect_type(result, "list")
  for (field in c("early_drops", "late_drops", "dips", "bumps", "waits",
                  "running_hot_sat", "chronic_sat", "tiered_summary")) {
    expect_s3_class(result[[field]], "data.frame")
  }
  expect_type(result$thresholds, "list")
  expect_true(all(c("min_impacted", "pct_sd", "chronic_fill_rate", "min_wait") %in%
                    names(result$thresholds)))
  expect_true("generated_at" %in% names(result$cache_info))
  expect_type(result$all_flagged_courses, "character")
  expect_identical(result$all_flagged_courses, sort(unique(result$all_flagged_courses)))

  # Later springs cannot supply the missing prior baseline for this fixture.
  # It also has no true waitlist demand in Spring 2020.
  expected_counts <- c(early_drops = 0L, late_drops = 0L, dips = 0L, bumps = 0L, waits = 0L)
  expect_equal(vapply(result[names(expected_counts)], nrow, integer(1)), expected_counts)

  expect_true(all(c("fill_rate", "fill_rate_mean", "sd_above_mean") %in%
                    names(result$running_hot_sat)))
  expect_true(all(result$running_hot_sat$sd_above_mean >= result$thresholds$pct_sd))
  expect_true(all(c("fill_rate", "n_chronic_terms") %in% names(result$chronic_sat)))
  expect_true(all(result$chronic_sat$fill_rate >= result$thresholds$chronic_fill_rate))
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
  result <- get_reg_stats(test_students, test_sections, opt, course_terms = test_course_terms)

  expect_equal(result$thresholds$min_impacted, 5)
  expect_equal(result$thresholds$pct_sd, 0.5)
  expect_equal(result$thresholds$min_wait, 2)
  expect_equal(result$cache_info$threshold_profile, "dashboard")
  expect_false(result$cache_info$using_standard_thresholds)
})


# =============================================================================
# get_reg_stats() custom thresholds tests
# =============================================================================

test_that("get_reg_stats applies custom thresholds and marks their cache metadata", {
  opt <- list(
    term = 202010,
    thresholds = list(
      min_impacted = 5, pct_sd = 0.5, chronic_fill_rate = 0.80, min_wait = 5
    )
  )
  result <- get_reg_stats(test_students, test_sections, opt, course_terms = test_course_terms)

  expect_equal(result$thresholds$min_impacted, 5)
  expect_equal(result$thresholds$pct_sd, 0.5)
  expect_equal(result$thresholds$chronic_fill_rate, 0.80)
  expect_equal(result$thresholds$min_wait, 5)
  expect_false(result$cache_info$using_standard_thresholds)
})


# =============================================================================
# Anomaly detection calculation tests
# =============================================================================


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
  result <- get_reg_stats(test_students, test_sections, opt, course_terms = test_course_terms)

  expect_equal(nrow(result$bumps), 0)
  expect_equal(result$baseline_info$n_hist_terms, 0L)
  expect_gt(result$baseline_info$unscored[["enrollment"]], 0)
})


# =============================================================================
# Edge cases
# =============================================================================

test_that("get_reg_stats handles empty student data gracefully", {
  empty_students <- test_students %>% filter(FALSE)
  opt            <- create_test_opt(list(term = 202010))

  result <- get_reg_stats(empty_students, test_sections, opt,
                          course_terms = course_terms_for(empty_students, test_sections))

  expect_type(result, "list")
})

test_that("get_reg_stats handles course filter — returns character all_flagged_courses", {
  opt    <- create_test_opt(list(term = 202010, course = "HIST 1110"))
  result <- get_reg_stats(test_students, test_sections, opt, course_terms = test_course_terms)

  expect_type(result$all_flagged_courses, "character")
})
