# CEDAR Caching System
# Functions to cache expensive computations like course-neighbors analysis

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
# Uses pre-computed global hashes (set at startup in global.R) when available
# to avoid re-running digest::digest() on the full data dimensions every lookup.
# Falls back to computing the hash inline if the globals are absent (e.g. in tests).
get_course_neighbors_cache_key <- function(course_code, students, courses, scope = list()) {
  students_hash <- if (exists("cedar_students_hash", envir = .GlobalEnv)) {
    cedar_students_hash
  } else {
    substr(digest::digest(list(nrow(students), ncol(students))), 1, 8)
  }

  courses_hash <- if (exists("cedar_sections_hash", envir = .GlobalEnv)) {
    cedar_sections_hash
  } else {
    substr(digest::digest(list(nrow(courses), ncol(courses))), 1, 8)
  }

  scope <- scope %||% list()
  campus <- sort(scope$course_campus %||% scope$campus %||% character(0))
  scope_key <- if (length(campus) > 0) {
    paste0("campus-", paste(gsub("[^A-Za-z0-9]+", "-", campus), collapse = "-"))
  } else {
    "campus-all"
  }

  paste0(gsub(" ", "_", course_code), "_", scope_key, "_", students_hash, "_", courses_hash)
}

# Save course-neighbors data to cache
save_course_neighbors_cache <- function(course_code, course_neighbors_data, students, courses, scope = list()) {
  tryCatch({
    cache_dir <- get_cache_dir()
    cache_key <- get_course_neighbors_cache_key(course_code, students, courses, scope)
    cache_file <- file.path(cache_dir, paste0("course_neighbors_", cache_key, ".qs"))
    
    # Use qs for fast serialization
    qs::qsave(course_neighbors_data, cache_file, preset = "fast")
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
        course_neighbors_data <- qs::qread(cache_file)
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
  pattern <- paste0("^course_neighbors_", safe_course, "_.*\\.qs$")
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
# Per-tab caching: one file per (dept, tab, week).
# File names: dept_{code}_{end_term}_{week}_{tab}.qs
#   e.g.  dept_HIST_202360_2026-W17_hc.qs
#         dept_HIST_202360_2026-W17_enrl.qs   (future)
#
# Cache stores tables + cfg only — no plots (too large) and no data_objects_filt
# (live data, never serialised).  Plots are rebuilt cheaply from tables on load.
# data_objects_filt is reconstructed via filter_data_objects() in dept-report.R.
#
# Cache is keyed by ISO week so it expires automatically each Monday without
# manual invalidation — weekly granularity is appropriate for longitudinal profiles.

# Generate the per-tab cache key.
get_dept_cache_key <- function(dept_code, tab, data_objects) {
  week_key <- format(Sys.Date(), "%Y-W%V")
  paste0("dept_", dept_code, "_", cedar_report_end_term, "_", week_key, "_", tab)
}

# Backward-compatible key helper for tests and older diagnostics that reason
# about the department profile cache as a single weekly report artifact.
get_dept_report_cache_key <- function(dept_code, data_objects) {
  get_dept_cache_key(dept_code, "hc", data_objects)
}

# Save one tab's data for a department.
# Strips plots and data_objects_filt before writing; atomic write via .tmp rename.
cache_dept_tab <- function(dept_code, tab, data, data_objects) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_dept_cache_key(dept_code, tab, data_objects), ".qs"))
    tmp_file   <- paste0(cache_file, ".tmp")
    data_to_save <- data[!names(data) %in% c("plots", "data_objects_filt")]
    qs::qsave(data_to_save, tmp_file, preset = "fast")
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
load_dept_tab_cache <- function(dept_code, tab, data_objects) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_file <- file.path(cache_dir, paste0(get_dept_cache_key(dept_code, tab, data_objects), ".qs"))
    if (file.exists(cache_file)) {
      data <- qs::qread(cache_file)
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

# Named wrappers — one per tab.  Add more as tabs are wired for caching.
cache_dept_headcount      <- function(dept_code, data, data_objects) cache_dept_tab(dept_code, "hc",   data, data_objects)
load_dept_headcount_cache <- function(dept_code, data_objects)       load_dept_tab_cache(dept_code, "hc",   data_objects)

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

# ---- Seatfinder Cache --------------------------------------------------------
#
# Keyed by data hash + the user's filter inputs so identical queries hit the
# cache across sessions.  Invalidates automatically when cedar_sections changes
# (cedar_sections_hash changes at startup after a data update).

get_seatfinder_cache_key <- function(opt) {
  sections_hash <- if (exists("cedar_sections_hash", envir = .GlobalEnv)) {
    cedar_sections_hash
  } else {
    "nohash"
  }
  opt_key <- paste(
    paste(sort(opt$course_campus  %||% ""), collapse = "-"),
    paste(sort(opt$course_college %||% ""), collapse = "-"),
    paste(sort(opt$dept           %||% ""), collapse = "-"),
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
    qs::qsave(data, tmp_file, preset = "fast")
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
      data <- qs::qread(cache_file)
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
