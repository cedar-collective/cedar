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

test_that("cache key contains course code (spaces replaced with underscores)", {
  key <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  expect_true(grepl("HIST_1110", key))
  expect_false(grepl("HIST 1110", key))  # raw space must not appear
})

test_that("cache key changes when student data dimensions change", {
  key_full    <- get_course_neighbors_cache_key("HIST 1110", test_students, test_sections)
  key_trimmed <- get_course_neighbors_cache_key("HIST 1110",
                                                head(test_students, 10),
                                                test_sections)

  expect_false(key_full == key_trimmed,
               info = "key must change when student row count changes")
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

test_that("dept report cache key is stable across row count changes within the same week", {
  # Cache keys use ISO week (not a data digest), so changing row counts
  # within the same week must NOT invalidate the cache. Dept profile caches
  # are longitudinal — weekly refresh is appropriate.
  smaller <- data_objects
  smaller[["cedar_students"]] <- head(data_objects[["cedar_students"]], 5)

  key_full    <- get_dept_report_cache_key("HIST", data_objects)
  key_smaller <- get_dept_report_cache_key("HIST", smaller)

  expect_true(key_full == key_smaller,
              info = "intra-week data refreshes must not bust the cache")
})

test_that("dept report cache key includes an ISO week component", {
  key <- get_dept_report_cache_key("HIST", data_objects)
  # Key format: "dept_HIST_<end_term>_<YYYY-Www>"
  expect_true(grepl("[0-9]{4}-W[0-9]{2}", key),
              info = "cache key should contain an ISO week string like 2026-W14")
})
