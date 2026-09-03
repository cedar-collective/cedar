# Tests for R/trunk/cache.R
#
# Covers:
#   - get_course_neighbors_cache_key(): key stability, invalidation, global hash path
#   - save/load/clear course-neighbors cache roundtrip
#   - dept report cache key + roundtrip
#
# Uses tempdir() for all disk writes — no production cache is touched.

context("Cache")

# Override cache dir to a per-test tempdir so tests don't touch production data.
# Restore after each test.
with_temp_cache <- function(code) {
  tmp <- tempfile()
  dir.create(tmp)
  old_base <- cedar_base_dir
  assign("cedar_base_dir", dirname(tmp), envir = .GlobalEnv)
  # get_cache_dir() builds: cedar_base_dir/data/cache — create that path
  cache_path <- file.path(dirname(tmp), "data", "cache")
  dir.create(cache_path, recursive = TRUE)
  on.exit({
    assign("cedar_base_dir", old_base, envir = .GlobalEnv)
    unlink(file.path(dirname(tmp), "data"), recursive = TRUE)
  }, add = TRUE)
  force(code)
}


# =============================================================================
# get_course_neighbors_cache_key()
# =============================================================================

test_that("cache key is stable for identical inputs", {
  key1 <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  key2 <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)

  expect_equal(key1, key2)
})

test_that("cache key differs for different courses", {
  k_hist <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  k_math <- get_course_neighbors_cache_key("MATH 1215", test_students, test_sections)

  expect_false(k_hist == k_math)
})

test_that("course-neighbors cache key differs for campus scopes", {
  k_abq <- get_course_neighbors_cache_key(
    "HIST 1110", test_students, test_sections,
    scope = list(course_campus = "ABQ")
  )
  k_va <- get_course_neighbors_cache_key(
    "HIST 1110", test_students, test_sections,
    scope = list(course_campus = "VA")
  )
  k_all <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)

  expect_false(k_abq == k_va)
  expect_false(k_abq == k_all)
  expect_true(grepl("campus-ABQ", k_abq))
})

test_that("course-neighbors cache key includes the observation edge", {
  old_edge <- get_course_neighbors_cache_key(
    "HIST 1110", test_students, test_sections,
    scope = list(course_campus = "ABQ", observation_end = 202080L)
  )
  new_edge <- get_course_neighbors_cache_key(
    "HIST 1110", test_students, test_sections,
    scope = list(course_campus = "ABQ", observation_end = 202110L)
  )

  expect_false(old_edge == new_edge)
})

test_that("cache key contains course code (spaces replaced with underscores)", {
  key <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  expect_true(grepl("^v[0-9]+_", key))
  expect_true(grepl("HIST_1110", key))
  expect_false(grepl("HIST 1110", key))  # raw space must not appear
})

test_that("course-neighbors cache key includes manual version", {
  key <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)

  expect_true(grepl(paste0("^v", cedar_course_neighbors_cache_version, "_"), key))
})

test_that("cache key changes when student data dimensions change", {
  key_full    <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  key_trimmed <- get_course_neighbors_cache_key("HIST 1110",
                                                head(test_students, 10),
                                                test_sections)

  expect_false(key_full == key_trimmed,
               info = "key must change when student row count changes")
})

test_that("cache key changes when relevant content changes at the same dimensions", {
  if (exists("cedar_students_hash", envir = .GlobalEnv))
    rm("cedar_students_hash", envir = .GlobalEnv)
  if (exists("cedar_sections_hash", envir = .GlobalEnv))
    rm("cedar_sections_hash", envir = .GlobalEnv)

  changed <- test_students
  changed$subject_course[[1]] <- "CHANGED 9999"
  original_key <- get_course_neighbors_cache_key(
    "HIST 1110", test_students, test_sections
  )
  changed_key <- get_course_neighbors_cache_key(
    "HIST 1110", changed, test_sections
  )

  expect_false(original_key == changed_key)
})

test_that("cache key uses pre-computed global hash when available", {
  # Set globals as global.R would at startup
  assign("cedar_students_hash", "aabbccdd", envir = .GlobalEnv)
  assign("cedar_sections_hash", "11223344", envir = .GlobalEnv)
  on.exit({
    rm("cedar_students_hash", envir = .GlobalEnv)
    rm("cedar_sections_hash", envir = .GlobalEnv)
  }, add = TRUE)

  key <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)

  expect_true(grepl("aabbccdd", key), info = "should embed students hash")
  expect_true(grepl("11223344", key), info = "should embed sections hash")
})

test_that("cache key falls back to digest when globals are absent", {
  # Ensure globals do NOT exist
  if (exists("cedar_students_hash", envir = .GlobalEnv))
    rm("cedar_students_hash", envir = .GlobalEnv)
  if (exists("cedar_sections_hash", envir = .GlobalEnv))
    rm("cedar_sections_hash", envir = .GlobalEnv)

  # Should not error — falls back to inline digest
  key <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  expect_true(is.character(key))
  expect_true(nchar(key) > 0)
})


# =============================================================================
# save / load / clear course-neighbors cache
# =============================================================================

test_that("save and load course-neighbors cache roundtrips data correctly", {
  with_temp_cache({
    payload <- list(data = test_sections[1:5, ], meta = "test")
    saved   <- save_course_neighbors_cache("HIST 1110", payload, test_students, test_sections)
    expect_true(saved)

    loaded <- load_course_neighbors_cache("HIST 1110", test_students, test_sections)
    expect_false(is.null(loaded))
    expect_equal(loaded$meta, "test")
    expect_equal(nrow(loaded$data), 5)
  })
})

test_that("load_course_neighbors_cache returns NULL on cache miss", {
  with_temp_cache({
    result <- load_course_neighbors_cache("NONEXISTENT 9999", test_students, test_sections)
    expect_null(result)
  })
})

test_that("clear_course_cache removes files for specified course only", {
  with_temp_cache({
    save_course_neighbors_cache("HIST 1110", list(x = 1), test_students, test_sections)
    save_course_neighbors_cache("MATH 1215", list(x = 2), test_students, test_sections)

    clear_course_cache("HIST 1110")

    expect_null(load_course_neighbors_cache("HIST 1110", test_students, test_sections))
    expect_false(is.null(load_course_neighbors_cache("MATH 1215", test_students, test_sections)))
  })
})

test_that("clear_all_caches removes all cache files", {
  with_temp_cache({
    save_course_neighbors_cache("HIST 1110", list(x = 1), test_students, test_sections)
    save_course_neighbors_cache("MATH 1215", list(x = 2), test_students, test_sections)

    clear_all_caches()

    expect_null(load_course_neighbors_cache("HIST 1110", test_students, test_sections))
    expect_null(load_course_neighbors_cache("MATH 1215", test_students, test_sections))
  })
})


# =============================================================================
# Dept report cache key
# =============================================================================

test_that("dept report cache key includes dept code and report end term", {
  key <- get_dept_report_cache_key("HIST", data_objects)

  expect_true(grepl("HIST",               key))
  expect_true(grepl(cedar_report_end_term, key))
})

test_that("dept report cache key differs for different departments", {
  k_hist <- get_dept_report_cache_key("HIST", data_objects)
  k_math <- get_dept_report_cache_key("MATH", data_objects)

  expect_false(k_hist == k_math)
})

test_that("dept report cache key changes across source-data row count changes", {
  smaller <- data_objects
  smaller[["cedar_students"]] <- head(data_objects[["cedar_students"]], 5)

  key_full    <- get_dept_report_cache_key("HIST", data_objects)
  key_smaller <- get_dept_report_cache_key("HIST", smaller)

  expect_false(key_full == key_smaller,
               info = "intra-week data refreshes must bust the cache")
})

test_that("dept report cache key includes version, tab, and scope", {
  key <- get_dept_report_cache_key("HIST", data_objects)
  expect_true(grepl(
    paste0("^dept_v", cedar_dept_cache_version, "_HIST_", cedar_report_end_term, "_hc_all_"),
    key
  ))
})

test_that("Dept Trends tab cache keys include result-affecting scope", {
  enrl_abq <- get_dept_cache_key(
    "HIST", "enrl", data_objects,
    list(campus = "ABQ", current_term = 202110L)
  )
  enrl_ea <- get_dept_cache_key(
    "HIST", "enrl", data_objects,
    list(campus = "EA", current_term = 202110L)
  )
  enrl_prior <- get_dept_cache_key(
    "HIST", "enrl", data_objects,
    list(campus = "ABQ", current_term = 202080L)
  )
  hc_abq <- get_dept_cache_key("HIST", "hc", data_objects, list(campus = "ABQ"))
  hc_ea <- get_dept_cache_key("HIST", "hc", data_objects, list(campus = "EA"))

  expect_false(enrl_abq == enrl_ea)
  expect_false(enrl_abq == enrl_prior)
  expect_equal(hc_abq, hc_ea,
               info = "program headcount does not use the course-campus filter")
})

test_that("Dept Trends tab cache persists data but strips plots and configuration", {
  with_temp_cache({
    opt <- list(campus = c("ABQ", "EA"), current_term = 202110L)
    payload <- list(
      plots = list(example = structure(list(), class = "plotly")),
      tables = list(example = tibble::tibble(x = 1)),
      palette = "Spectral",
      data_objects_filt = data_objects
    )

    expect_true(cache_dept_enrollment("HIST", payload, data_objects, opt))
    loaded <- load_dept_enrollment_cache("HIST", data_objects, opt)

    expect_equal(loaded$tables$example$x, 1)
    expect_false("plots" %in% names(loaded))
    expect_false("palette" %in% names(loaded))
    expect_false("data_objects_filt" %in% names(loaded))
  })
})


# =============================================================================
# Dept Dashboard cache
# =============================================================================

test_that("dept dashboard cache key includes request scope and daily date", {
  key <- get_dept_dashboard_cache_key(
    list(dept_code = "HIST", campus = c("EA", "ABQ"), term = 202110L),
    data_objects,
    cache_date = as.Date("2026-07-30")
  )

  expect_true(grepl("^dashboard_dept_HIST_202110_ABQ-EA_20260730_", key))
})

test_that("dept dashboard cache key differs by term, campus, and date", {
  base <- get_dept_dashboard_cache_key(
    list(dept_code = "HIST", campus = c("ABQ", "EA"), term = 202110L),
    data_objects,
    cache_date = as.Date("2026-07-30")
  )
  other_term <- get_dept_dashboard_cache_key(
    list(dept_code = "HIST", campus = c("ABQ", "EA"), term = 202080L),
    data_objects,
    cache_date = as.Date("2026-07-30")
  )
  other_campus <- get_dept_dashboard_cache_key(
    list(dept_code = "HIST", campus = "ABQ", term = 202110L),
    data_objects,
    cache_date = as.Date("2026-07-30")
  )
  other_date <- get_dept_dashboard_cache_key(
    list(dept_code = "HIST", campus = c("ABQ", "EA"), term = 202110L),
    data_objects,
    cache_date = as.Date("2026-07-31")
  )

  expect_false(base == other_term)
  expect_false(base == other_campus)
  expect_false(base == other_date)
})

test_that("dept dashboard cache save/load roundtrips one dashboard payload", {
  with_temp_cache({
    opt <- list(dept_code = "HIST", campus = c("ABQ", "EA"), term = 202110L)
    payload <- list(
      dept_code = "HIST",
      current_term = 202110L,
      headcount_summary = data.frame(group = "Undergraduate Majors", current_count = 12)
    )

    expect_true(save_dept_dashboard_cache(opt, payload, data_objects))
    loaded <- load_dept_dashboard_cache(opt, data_objects)

    expect_false(is.null(loaded))
    expect_equal(loaded$dept_code, "HIST")
    expect_equal(loaded$current_term, 202110L)
    expect_equal(loaded$headcount_summary$current_count, 12)
  })
})

test_that("clear_dept_dashboard_cache removes dashboard files only", {
  with_temp_cache({
    dashboard_opt <- list(dept_code = "HIST", campus = "ABQ", term = 202110L)
    save_dept_dashboard_cache(dashboard_opt, list(x = 1), data_objects)
    cache_dept_headcount("HIST", list(tables = list(), dept_code = "HIST"), data_objects)

    expect_equal(clear_dept_dashboard_cache("HIST"), 1)
    expect_null(load_dept_dashboard_cache(dashboard_opt, data_objects))
    expect_false(is.null(load_dept_headcount_cache("HIST", data_objects)))
  })
})


# =============================================================================
# Seatfinder cache
# =============================================================================

test_that("seatfinder cache key includes manual version and sections hash", {
  had_hash <- exists("cedar_sections_hash", envir = .GlobalEnv, inherits = FALSE)
  old_hash <- if (had_hash) get("cedar_sections_hash", envir = .GlobalEnv) else NULL
  had_version <- exists("cedar_seatfinder_cache_version", envir = .GlobalEnv, inherits = FALSE)
  old_version <- if (had_version) {
    get("cedar_seatfinder_cache_version", envir = .GlobalEnv)
  } else {
    NULL
  }
  on.exit({
    if (had_hash) {
      assign("cedar_sections_hash", old_hash, envir = .GlobalEnv)
    } else if (exists("cedar_sections_hash", envir = .GlobalEnv, inherits = FALSE)) {
      rm("cedar_sections_hash", envir = .GlobalEnv)
    }
    if (had_version) {
      assign("cedar_seatfinder_cache_version", old_version, envir = .GlobalEnv)
    } else if (exists("cedar_seatfinder_cache_version", envir = .GlobalEnv, inherits = FALSE)) {
      rm("cedar_seatfinder_cache_version", envir = .GlobalEnv)
    }
  }, add = TRUE)

  assign("cedar_sections_hash", "sections-a", envir = .GlobalEnv)
  assign("cedar_seatfinder_cache_version", 2L, envir = .GlobalEnv)

  key <- get_seatfinder_cache_key(list(
    course_campus = "ABQ",
    dept_code = "HIST",
    term = 202580L
  ))

  assign("cedar_seatfinder_cache_version", 999L, envir = .GlobalEnv)
  bumped_key <- get_seatfinder_cache_key(list(
    course_campus = "ABQ",
    dept_code = "HIST",
    term = 202580L
  ))

  expect_true(grepl("sections-a$", key))
  expect_true(grepl("^sf_", key))
  expect_false(identical(key, bumped_key))
})

test_that("seatfinder discards rates cached before term-aware attempt counting", {
  current_version <- cedar_seatfinder_cache_version
  on.exit(assign("cedar_seatfinder_cache_version", current_version, envir = .GlobalEnv), add = TRUE)

  with_temp_cache({
    opt <- list(course_campus = "ABQ", dept_code = "HIST", term = 202580L)
    assign("cedar_seatfinder_cache_version", 2L, envir = .GlobalEnv)
    expect_true(save_seatfinder_cache(opt, list(marker = "pre-term-dedup")))
    expect_equal(load_seatfinder_cache(opt)$marker, "pre-term-dedup")

    assign("cedar_seatfinder_cache_version", current_version, envir = .GlobalEnv)
    expect_null(load_seatfinder_cache(opt))
  })
})

test_that("seatfinder cache misses after a data hash change", {
  had_hash <- exists("cedar_sections_hash", envir = .GlobalEnv, inherits = FALSE)
  old_hash <- if (had_hash) get("cedar_sections_hash", envir = .GlobalEnv) else NULL
  on.exit({
    if (had_hash) {
      assign("cedar_sections_hash", old_hash, envir = .GlobalEnv)
    } else if (exists("cedar_sections_hash", envir = .GlobalEnv, inherits = FALSE)) {
      rm("cedar_sections_hash", envir = .GlobalEnv)
    }
  }, add = TRUE)

  with_temp_cache({
    opt <- list(course_campus = "ABQ", dept_code = "HIST", term = 202580L)
    assign("cedar_sections_hash", "before-refresh", envir = .GlobalEnv)

    expect_true(save_seatfinder_cache(opt, list(marker = "old-cache")))
    expect_equal(load_seatfinder_cache(opt)$marker, "old-cache")

    assign("cedar_sections_hash", "after-refresh", envir = .GlobalEnv)
    expect_null(load_seatfinder_cache(opt))
  })
})
