# CEDAR Caching System
# Functions to cache expensive computations like course-neighbors analysis

# v2 filters to final registered rows and adds exact concurrent-course
# student-term denominators used by the Course Dynamics treemap/table.
# v3 includes every analytical scope field and source-content fingerprints.
cedar_course_neighbors_cache_version <- 3L

# Regstats v2 uses a separate prior-only baseline for every reported term;
# v3 preserves one reporting row when source sections carry different titles;
# v4 aligns saturation to class-list census and adds lifecycle drop-rate context.
# v5 aligns High Waitlists to shared class-list true demand.
cedar_regstats_cache_version <- 5L

course_neighbors_content_hash <- function(df, relevant_cols) {
  cols <- intersect(relevant_cols, names(df))
  payload <- if (length(cols) > 0L) df[, cols, drop = FALSE] else df
  substr(digest::digest(payload), 1, 10)
}

cedar_cache_object_hash <- function(value, source_fingerprint = NULL) {
  dimensions <- if (is.data.frame(value)) {
    list(nrow(value), ncol(value), source_fingerprint)
  } else {
    list(length(value), source_fingerprint)
  }
  substr(digest::digest(dimensions), 1, 10)
}

# Get cache directory path
get_cache_dir <- function() {
  cache_dir <- file.path(cedar_base_dir, "data", "cache")
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE)
    message("[cache.R] Created cache directory: ", cache_dir)
  }
  return(cache_dir)
}

# Generate cache key for course-neighbors data.
# Bump cedar_course_neighbors_cache_version whenever course-neighbor cached
# payload shape or computation logic changes. Data hashes handle source refreshes;
# the manual version handles code changes against the same data.
# Uses pre-computed global hashes (set at startup in global.R) when available
# to avoid re-running digest::digest() on the full data dimensions every lookup.
# Falls back to computing the hash inline if the globals are absent (e.g. in tests).
get_course_neighbors_cache_key <- function(course_code, students, courses, scope = list()) {
  students_hash <- if (exists("cedar_students_hash", envir = .GlobalEnv)) {
    cedar_students_hash
  } else {
    course_neighbors_content_hash(
      students,
      c("student_id", "term", "subject_course", "campus", "college",
        "term_type", "student_classification", "registration_status_code")
    )
  }

  courses_hash <- if (exists("cedar_sections_hash", envir = .GlobalEnv)) {
    cedar_sections_hash
  } else {
    course_neighbors_content_hash(
      courses,
      c("term", "subject_course", "campus", "college", "department", "course_title")
    )
  }

  scope <- scope %||% list()
  campus <- sort(scope$course_campus %||% scope$campus %||% character(0))
  campus_key <- if (length(campus) > 0) {
    paste0("campus-", paste(gsub("[^A-Za-z0-9]+", "-", campus), collapse = "-"))
  } else {
    "campus-all"
  }
  normalized_scope <- scope[sort(names(scope))]
  normalized_scope <- lapply(normalized_scope, function(x) {
    if (length(x) > 1L) sort(as.character(x)) else as.character(x)
  })
  scope_key <- paste0(campus_key, "-scope-",
                      substr(digest::digest(normalized_scope), 1, 10))

  paste0("v", cedar_course_neighbors_cache_version, "_",
         gsub(" ", "_", course_code), "_", scope_key, "_",
         students_hash, "_", courses_hash)
}

# Save course-neighbors data to cache
save_course_neighbors_cache <- function(course_code, course_neighbors_data, students, courses, scope = list()) {
  tryCatch({
    cache_dir <- get_cache_dir()
    cache_key <- get_course_neighbors_cache_key(course_code, students, courses, scope)
    cache_file <- file.path(cache_dir, paste0("course_neighbors_", cache_key, ".qs"))
    
    # Use qs for fast serialization
    qs2::qs_save(course_neighbors_data, cache_file)
    message("[cache.R] Saved course-neighbors cache for ", course_code, " to ", basename(cache_file))
    
    return(TRUE)
  }, error = function(e) {
    message("[cache.R] Error saving cache: ", e$message)
    return(FALSE)
  })
}

# Load course-neighbors data from cache
load_course_neighbors_cache <- function(course_code, students, courses, scope = list()) {
  tryCatch({
    cache_dir <- get_cache_dir()
    cache_key <- get_course_neighbors_cache_key(course_code, students, courses, scope)
    cache_file <- file.path(cache_dir, paste0("course_neighbors_", cache_key, ".qs"))
    
    if (file.exists(cache_file)) {
      # Check if cache is recent (e.g., less than 7 days old)
      cache_age_days <- as.numeric(difftime(Sys.time(), file.mtime(cache_file), units = "days"))
      
      if (cache_age_days < 7) {
        course_neighbors_data <- qs2::qs_read(cache_file)
        message("[cache.R] Loaded course-neighbors cache for ", course_code, " (", round(cache_age_days, 1), " days old)")
        return(course_neighbors_data)
      } else {
        message("[cache.R] Cache for ", course_code, " is stale (", round(cache_age_days, 1), " days old)")
        # Optionally delete stale cache
        file.remove(cache_file)
      }
    } else {
      message("[cache.R] No cache found for ", course_code)
    }
    
    return(NULL)
  }, error = function(e) {
    message("[cache.R] Error loading cache: ", e$message)
    return(NULL)
  })
}

# Clear all cached data
clear_all_caches <- function() {
  cache_dir <- get_cache_dir()
  cache_files <- list.files(cache_dir, pattern = "\\.qs$", full.names = TRUE)
  
  if (length(cache_files) > 0) {
    file.remove(cache_files)
    message("[cache.R] Cleared ", length(cache_files), " cache files")
  } else {
    message("[cache.R] No cache files to clear")
  }
}

# Clear cache for specific course
clear_course_cache <- function(course_code) {
  cache_dir <- get_cache_dir()
  safe_course <- gsub(" ", "_", course_code)
  pattern <- paste0("^course_neighbors_(v[0-9]+_)?", safe_course, "_.*\\.qs$")
  cache_files <- list.files(cache_dir, pattern = pattern, full.names = TRUE)
  
  if (length(cache_files) > 0) {
    file.remove(cache_files)
    message("[cache.R] Cleared ", length(cache_files), " cache file(s) for ", course_code)
  } else {
    message("[cache.R] No cache files found for ", course_code)
  }
}

# ---- Dept Tab Cache ----------------------------------------------------------
#
# Per-tab caching: one file per (dept, tab, analytical scope, data snapshot).
# File names: dept_v{version}_{code}_{end_term}_{tab}_{scope}_{hash}.qs
#   e.g.  dept_v4_HIST_202680_hc_all_a1b2c3d4e5f6.qs
#         dept_v4_HIST_202680_enrl_ABQ-EA_a1b2c3d4e5f6.qs
#
# Cache stores tables + cfg only — no plots (too large) and no data_objects_filt
# (live data, never serialised).  Plots are rebuilt cheaply from tables on load.
# data_objects_filt is reconstructed via filter_data_objects() in dept-trends.R.
#
# Cache lifetime is content-addressed: source-data fingerprints, report-window
# settings, result-affecting scope, and a manual version determine validity.
# This avoids throwing away unchanged longitudinal work every Monday. The
# Enrollment tab also carries the calendar year because its five-year SCH view
# is defined relative to the current year.

# Generate the per-tab cache key.
# Bump when the cached payload's SHAPE or MEANING changes, so stale files are
# ignored instead of silently reused. Earlier keys were only dept + term + ISO
# week, so a payload written early in the week survived code and data changes.
#   v2 — payload no longer carries `palette` (it is config, not data; a stored
#        "Spectral" from an older config was overriding the CEDAR palette on
#        every Dept Trends chart that takes a palette argument).
#   v3 — key includes source-data dimension hashes, matching the other cache
#        families. Corrected same-week data should invalidate without requiring
#        a manual cache clear or waiting for Monday.
#   v4 — all main Dept Trends tab payloads are cacheable; keys include the
#        tab-specific campus/current-term scope and no longer expire by week.
cedar_dept_cache_version <- 4L

normalize_dept_cache_scope <- function(tab, opt = list()) {
  opt <- opt %||% list()
  common <- list(
    prog = sort(as.character(opt[["prog"]] %||% character(0)))
  )

  if (identical(tab, "enrl")) {
    return(c(common, list(
      campus = sort(as.character(opt[["campus"]] %||% character(0))),
      current_term = as.character(opt[["current_term"]] %||% character(0)),
      analysis_year = format(Sys.Date(), "%Y")
    )))
  }
  if (identical(tab, "ch")) {
    return(c(common, list(
      campus = sort(as.character(opt[["campus"]] %||% character(0)))
    )))
  }
  common
}

get_dept_cache_key <- function(dept_code, tab, data_objects, opt = list()) {
  scope <- normalize_dept_cache_scope(tab, opt)
  key_obj <- list(
    version = cedar_dept_cache_version,
    dept = dept_code,
    start_term = cedar_report_start_term,
    end_term = cedar_report_end_term,
    tab = tab,
    scope = scope,
    students_hash = get_cache_table_dim_hash(data_objects, "cedar_students", "cedar_students_hash"),
    sections_hash = get_cache_table_dim_hash(data_objects, "cedar_sections", "cedar_sections_hash"),
    programs_hash = get_cache_table_dim_hash(data_objects, "cedar_programs", "cedar_programs_hash"),
    degrees_hash = get_cache_table_dim_hash(data_objects, "cedar_degrees", "cedar_degrees_hash"),
    faculty_hash = get_cache_table_dim_hash(data_objects, "cedar_faculty", "cedar_faculty_hash"),
    lookups_hash = get_cache_table_dim_hash(data_objects, "cedar_lookups", "cedar_lookups_hash")
  )
  scope_token <- cache_safe_token(scope[["campus"]] %||% character(0))
  paste0("dept_v", cedar_dept_cache_version, "_", dept_code, "_",
         cedar_report_end_term, "_", tab, "_", scope_token, "_",
         substr(digest::digest(key_obj), 1, 12))
}

# Backward-compatible key helper for diagnostics that treat Headcount as the
# department profile's base artifact.
get_dept_report_cache_key <- function(dept_code, data_objects, opt = list()) {
  get_dept_cache_key(dept_code, "hc", data_objects, opt)
}

# Save one tab's data for a department.
# Strips plots, data_objects_filt, and palette before writing; atomic write via
# .tmp rename.
#
# `palette` is deliberately NOT persisted: it comes from cedar_report_palette
# (configuration), not from the data. Storing it meant a cache written under an
# older config kept forcing that palette on every chart rebuilt from it, long
# after the config changed. Readers take the palette from the live config.
cache_dept_tab <- function(dept_code, tab, data, data_objects, opt = list()) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_dept_cache_key(dept_code, tab, data_objects, opt), ".qs"))
    tmp_file   <- paste0(cache_file, ".tmp")
    data_to_save <- data[!names(data) %in% c("plots", "data_objects_filt", "palette")]
    qs2::qs_save(data_to_save, tmp_file)
    file.rename(tmp_file, cache_file)
    size_mb <- round(file.size(cache_file) / 1024 / 1024, 1)
    message("[cache.R] Saved dept ", tab, " cache for ", dept_code,
            " (", basename(cache_file), ", ", size_mb, " MB)")
    TRUE
  }, error = function(e) {
    message("[cache.R] Error saving dept ", tab, " cache: ", e$message)
    FALSE
  })
}

# Load one tab's cached data. Returns NULL on miss or error.
load_dept_tab_cache <- function(dept_code, tab, data_objects, opt = list()) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_dept_cache_key(dept_code, tab, data_objects, opt), ".qs"))
    if (file.exists(cache_file)) {
      data <- qs2::qs_read(cache_file)
      message("[cache.R] Loaded dept ", tab, " cache for ", dept_code,
              " (", basename(cache_file), ")")
      return(data)
    }
    message("[cache.R] No dept ", tab, " cache for ", dept_code)
    NULL
  }, error = function(e) {
    message("[cache.R] Error loading dept ", tab, " cache: ", e$message)
    NULL
  })
}

# Named wrappers keep callers explicit about which payload they are storing.
cache_dept_headcount      <- function(dept_code, data, data_objects, opt = list()) cache_dept_tab(dept_code, "hc", data, data_objects, opt)
load_dept_headcount_cache <- function(dept_code, data_objects, opt = list()) load_dept_tab_cache(dept_code, "hc", data_objects, opt)
cache_dept_enrollment      <- function(dept_code, data, data_objects, opt = list()) cache_dept_tab(dept_code, "enrl", data, data_objects, opt)
load_dept_enrollment_cache <- function(dept_code, data_objects, opt = list()) load_dept_tab_cache(dept_code, "enrl", data_objects, opt)
cache_dept_degrees      <- function(dept_code, data, data_objects, opt = list()) cache_dept_tab(dept_code, "deg", data, data_objects, opt)
load_dept_degrees_cache <- function(dept_code, data_objects, opt = list()) load_dept_tab_cache(dept_code, "deg", data_objects, opt)
cache_dept_credit_hours      <- function(dept_code, data, data_objects, opt = list()) cache_dept_tab(dept_code, "ch", data, data_objects, opt)
load_dept_credit_hours_cache <- function(dept_code, data_objects, opt = list()) load_dept_tab_cache(dept_code, "ch", data_objects, opt)
cache_dept_demographics      <- function(dept_code, data, data_objects, opt = list()) cache_dept_tab(dept_code, "demo", data, data_objects, opt)
load_dept_demographics_cache <- function(dept_code, data_objects, opt = list()) load_dept_tab_cache(dept_code, "demo", data_objects, opt)

# ---- Dept Dashboard Cache ---------------------------------------------------
#
# Dept Dashboard is the selected-term home for chairs, so this cache is keyed to
# one explicit dashboard request: dept + campus scope + snapshot term + date.
# The date key makes the cache naturally daily, while the data dimension hashes
# separate cache files when the app restarts against changed CEDAR tables.

# v4 — CEDAR_PALETTE slot order changed in v2; v3 briefly added a Dept Trends
# student_donuts bundle to the dashboard payload; v4 restores the dashboard to
# its headcount-line payload. Bump on any palette or plot shape change.
# v5 invalidates the embedded Regstats flags after the prior-history repair.
# v6 invalidates embedded flags after title enrichment stopped duplicating rows.
# v7 carries source-aligned saturation flags and lifecycle drop-rate context.
# v8 aligns high-waitlist flags with class-list true demand.
cedar_dept_dashboard_cache_version <- 8L

cache_value_or <- function(x, default) {
  if (is.null(x) || length(x) == 0) default else x
}

cache_safe_token <- function(x, default = "all") {
  x <- as.character(x)
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0) return(default)
  gsub("[^A-Za-z0-9]+", "-", paste(sort(unique(x)), collapse = "-"))
}

get_cache_table_dim_hash <- function(data_objects, table_name, global_hash_name) {
  if (exists(global_hash_name, envir = .GlobalEnv)) {
    return(get(global_hash_name, envir = .GlobalEnv))
  }
  tbl <- data_objects[[table_name]]
  if (is.null(tbl)) return("missing")
  cedar_cache_object_hash(tbl)
}

get_dept_dashboard_cache_key <- function(opt, data_objects, cache_date = Sys.Date()) {
  dept <- cache_value_or(opt[["dept_code"]], "unknown")
  term <- cache_value_or(opt[["term"]], if (exists("cedar_current_term", envir = .GlobalEnv)) {
    cedar_current_term
  } else {
    "unknown-term"
  })
  campus <- cache_value_or(opt[["campus"]], opt[["course_campus"]])
  campus_key <- cache_safe_token(campus)
  date_key <- format(as.Date(cache_date), "%Y%m%d")
  campus_values <- cache_value_or(campus, character(0))

  key_obj <- list(
    version = cedar_dept_dashboard_cache_version,
    dept = dept,
    term = as.character(term),
    campus = sort(campus_values),
    date = date_key,
    students_hash = get_cache_table_dim_hash(data_objects, "cedar_students", "cedar_students_hash"),
    sections_hash = get_cache_table_dim_hash(data_objects, "cedar_sections", "cedar_sections_hash"),
    programs_hash = get_cache_table_dim_hash(data_objects, "cedar_programs", "cedar_programs_hash")
  )

  paste0(
    "dashboard_dept_",
    cache_safe_token(dept, "unknown"),
    "_", cache_safe_token(term, "unknown-term"),
    "_", campus_key,
    "_", date_key,
    "_", substr(digest::digest(key_obj), 1, 12)
  )
}

save_dept_dashboard_cache <- function(opt, data, data_objects) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_dept_dashboard_cache_key(opt, data_objects), ".qs"))
    tmp_file   <- paste0(cache_file, ".tmp")
    qs2::qs_save(data, tmp_file)
    file.rename(tmp_file, cache_file)
    size_mb <- round(file.size(cache_file) / 1024 / 1024, 1)
    message("[cache.R] Saved dept dashboard cache (", basename(cache_file), ", ", size_mb, " MB)")
    TRUE
  }, error = function(e) {
    message("[cache.R] Error saving dept dashboard cache: ", e$message)
    FALSE
  })
}

load_dept_dashboard_cache <- function(opt, data_objects) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_dept_dashboard_cache_key(opt, data_objects), ".qs"))
    if (file.exists(cache_file)) {
      data <- qs2::qs_read(cache_file)
      message("[cache.R] Loaded dept dashboard cache (", basename(cache_file), ")")
      return(data)
    }
    message("[cache.R] No dept dashboard cache for this query")
    NULL
  }, error = function(e) {
    message("[cache.R] Error loading dept dashboard cache: ", e$message)
    NULL
  })
}

clear_dept_dashboard_cache <- function(dept_code = NULL) {
  cache_dir <- get_cache_dir()
  pattern <- if (is.null(dept_code)) {
    "^dashboard_dept_.*\\.(qs|tmp)$"
  } else {
    paste0("^dashboard_dept_", cache_safe_token(dept_code, "unknown"), "_.*\\.(qs|tmp)$")
  }
  cache_files <- list.files(cache_dir, pattern = pattern, full.names = TRUE)
  if (length(cache_files) > 0) {
    file.remove(cache_files)
    message("[cache.R] Cleared ", length(cache_files), " dept dashboard cache file(s)")
  } else {
    message("[cache.R] No dept dashboard cache files to clear")
  }
  invisible(length(cache_files))
}

# Clear dept cache files.  Pass dept_code to clear one dept, NULL for all.
# Matches all tab suffixes (_hc, _enrl, _deg, ...) and orphaned .tmp files.
clear_dept_cache <- function(dept_code = NULL) {
  cache_dir   <- get_cache_dir()
  qs_pattern  <- if (is.null(dept_code)) "^dept_.*\\.qs$"  else paste0("^dept_", dept_code, "_.*\\.qs$")
  tmp_pattern <- if (is.null(dept_code)) "^dept_.*\\.tmp$" else paste0("^dept_", dept_code, "_.*\\.tmp$")
  cache_files <- c(
    list.files(cache_dir, pattern = qs_pattern,  full.names = TRUE),
    list.files(cache_dir, pattern = tmp_pattern, full.names = TRUE)
  )
  if (length(cache_files) > 0) {
    file.remove(cache_files)
    message("[cache.R] Cleared ", length(cache_files), " dept cache file(s)")
  } else {
    message("[cache.R] No dept cache files to clear")
  }
}

# ---- Pathways Population Benchmark Cache ------------------------------------
#
# College comparison benchmarks are intentionally stable within a configured
# CEDAR term. Programs/degrees may refresh daily, but these benchmarks should
# roll when cedar_current_term changes or when the manual version is bumped.

cedar_population_benchmark_cache_version <- 1L

get_population_benchmark_cache_key <- function(college, opt = list()) {
  term_key <- if (exists("cedar_current_term", envir = .GlobalEnv)) {
    as.character(cedar_current_term)
  } else {
    "unknown-term"
  }
  key_obj <- list(
    version = cedar_population_benchmark_cache_version,
    term = term_key,
    college = college,
    campus = sort(opt$campus %||% character(0)),
    student_level = sort(opt$student_level %||% character(0)),
    outcomes = sort(opt$outcomes %||% character(0))
  )
  paste0("pathways_pop_benchmark_", substr(digest::digest(key_obj), 1, 16))
}

save_population_benchmark_cache <- function(college, opt, benchmark) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_population_benchmark_cache_key(college, opt), ".qs"))
    tmp_file   <- paste0(cache_file, ".tmp")
    qs2::qs_save(benchmark, tmp_file)
    file.rename(tmp_file, cache_file)
    message("[cache.R] Saved pathways population benchmark cache for ", college,
            " (", basename(cache_file), ")")
    TRUE
  }, error = function(e) {
    message("[cache.R] Error saving pathways population benchmark cache: ", e$message)
    FALSE
  })
}

load_population_benchmark_cache <- function(college, opt) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_population_benchmark_cache_key(college, opt), ".qs"))
    if (file.exists(cache_file)) {
      benchmark <- qs2::qs_read(cache_file)
      message("[cache.R] Loaded pathways population benchmark cache for ", college,
              " (", basename(cache_file), ")")
      return(benchmark)
    }
    message("[cache.R] No pathways population benchmark cache for ", college)
    NULL
  }, error = function(e) {
    message("[cache.R] Error loading pathways population benchmark cache: ", e$message)
    NULL
  })
}

clear_population_benchmark_cache <- function() {
  cache_dir <- get_cache_dir()
  cache_files <- c(
    list.files(cache_dir, pattern = "^pathways_pop_benchmark_.*\\.qs$", full.names = TRUE),
    list.files(cache_dir, pattern = "^pathways_pop_benchmark_.*\\.tmp$", full.names = TRUE)
  )
  if (length(cache_files) > 0) {
    file.remove(cache_files)
    message("[cache.R] Cleared ", length(cache_files), " pathways population benchmark cache file(s)")
  } else {
    message("[cache.R] No pathways population benchmark cache files to clear")
  }
  invisible(length(cache_files))
}

# ---- Seatfinder Cache --------------------------------------------------------
#
# Keyed by data hash + the user's filter inputs so identical queries hit the
# cache across sessions.  Invalidates automatically when cedar_sections changes
# (cedar_sections_hash changes at startup after a data update).

# v3 discards historical DFW rates computed before term-aware attempt deduplication.
cedar_seatfinder_cache_version <- 3L

get_seatfinder_cache_key <- function(opt) {
  sections_hash <- if (exists("cedar_sections_hash", envir = .GlobalEnv)) {
    cedar_sections_hash
  } else {
    "nohash"
  }
  opt_key <- paste(
    paste0("v", cedar_seatfinder_cache_version),
    paste(sort(opt$course_campus  %||% ""), collapse = "-"),
    paste(sort(opt$course_college %||% ""), collapse = "-"),
    paste(sort(opt$dept_code      %||% ""), collapse = "-"),
    paste(sort(opt$term           %||% ""), collapse = "-"),
    paste(sort(opt$pt             %||% ""), collapse = "-"),
    paste(sort(opt$im             %||% ""), collapse = "-"),
    paste(sort(opt$level          %||% ""), collapse = "-"),
    sep = "_"
  )
  paste0("sf_", substr(digest::digest(opt_key), 1, 12), "_", sections_hash)
}

save_seatfinder_cache <- function(opt, data) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_seatfinder_cache_key(opt), ".qs"))
    tmp_file   <- paste0(cache_file, ".tmp")
    qs2::qs_save(data, tmp_file)
    file.rename(tmp_file, cache_file)
    size_mb <- round(file.size(cache_file) / 1024 / 1024, 1)
    message("[cache.R] Saved seatfinder cache (", basename(cache_file), ", ", size_mb, " MB)")
    TRUE
  }, error = function(e) {
    message("[cache.R] Error saving seatfinder cache: ", e$message)
    FALSE
  })
}

load_seatfinder_cache <- function(opt) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_seatfinder_cache_key(opt), ".qs"))
    if (file.exists(cache_file)) {
      data <- qs2::qs_read(cache_file)
      message("[cache.R] Loaded seatfinder cache (", basename(cache_file), ")")
      return(data)
    }
    message("[cache.R] No seatfinder cache for this query")
    NULL
  }, error = function(e) {
    message("[cache.R] Error loading seatfinder cache: ", e$message)
    NULL
  })
}

# ---- Cache Statistics --------------------------------------------------------

# Get cache statistics
get_cache_stats <- function() {
  cache_dir <- get_cache_dir()
  cache_files <- list.files(cache_dir, pattern = "\\.qs$", full.names = TRUE)
  
  if (length(cache_files) == 0) {
    return(data.frame(
      message = "No cached data",
      stringsAsFactors = FALSE
    ))
  }
  
  stats <- data.frame(
    file = basename(cache_files),
    size_mb = file.size(cache_files) / 1024 / 1024,
    modified = file.mtime(cache_files),
    age_days = as.numeric(difftime(Sys.time(), file.mtime(cache_files), units = "days")),
    stringsAsFactors = FALSE
  )
  
  stats <- stats[order(stats$modified, decreasing = TRUE), ]
  rownames(stats) <- NULL
  
  return(stats)
}
