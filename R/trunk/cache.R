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
get_course_neighbors_cache_key <- function(course_code, students, courses) {
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

  paste0(gsub(" ", "_", course_code), "_", students_hash, "_", courses_hash)
}

# Save course-neighbors data to cache
save_course_neighbors_cache <- function(course_code, course_neighbors_data, students, courses) {
  tryCatch({
    cache_dir <- get_cache_dir()
    cache_key <- get_course_neighbors_cache_key(course_code, students, courses)
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
load_course_neighbors_cache <- function(course_code, students, courses) {
  tryCatch({
    cache_dir <- get_cache_dir()
    cache_key <- get_course_neighbors_cache_key(course_code, students, courses)
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

# ---- Dept Report Cache -------------------------------------------------------

# Strip source data that ggplotly() embeds in plotly objects.
# ggplotly() stores the original data frames in x$attrs / x$cur_data / x$visdat
# for interactive data manipulation. For display-only rendering in Shiny these
# are redundant — the traces in x$data are already built. Stripping them
# reduces serialized size dramatically (often 10-50x).
# Generate cache key for a dept report.
# Key encodes dept, report end term, and ISO week number (YYYY-WNN).
# Cache is valid for one week; expires automatically at the start of each new week.
# Dept profiles are intended for longitudinal analysis, not real-time data — weekly
# granularity is appropriate and avoids daily invalidation from minor data updates.
get_dept_report_cache_key <- function(dept_code, data_objects) {
  week_key <- format(Sys.Date(), "%Y-W%V")
  paste0("dept_", dept_code, "_", cedar_report_end_term, "_", week_key)
}

# Save a dept report to the disk cache (tables + cfg only — no plots).
# Plots are excluded because plotly objects are large and slow to deserialize.
# They are regenerated cheaply from tables on cache hit.
cache_dept_report <- function(dept_code, data, data_objects) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_key  <- get_dept_report_cache_key(dept_code, data_objects)
    cache_file <- file.path(cache_dir, paste0(cache_key, ".qs"))
    tmp_file   <- paste0(cache_file, ".tmp")

    # Strip plots — only cache tables + cfg
    data_to_save <- data[names(data) != "plots"]

    # Atomic write: write to .tmp then rename so a crash never leaves a partial file
    qs::qsave(data_to_save, tmp_file, preset = "fast")
    file.rename(tmp_file, cache_file)

    size_mb <- round(file.size(cache_file) / 1024 / 1024, 1)
    message("[cache.R] Saved dept report cache for ", dept_code,
            " (", basename(cache_file), ", ", size_mb, " MB, tables only)")
    TRUE
  }, error = function(e) {
    message("[cache.R] Error saving dept report cache: ", e$message)
    FALSE
  })
}

# Load a dept report from the disk cache.
# Returns list with tables + cfg (no plots). Returns NULL on miss.
load_dept_report_cache <- function(dept_code, data_objects) {
  tryCatch({
    cache_dir  <- get_cache_dir()
    cache_key  <- get_dept_report_cache_key(dept_code, data_objects)
    cache_file <- file.path(cache_dir, paste0(cache_key, ".qs"))
    if (file.exists(cache_file)) {
      data <- qs::qread(cache_file)
      message("[cache.R] Loaded dept report cache for ", dept_code, " (", basename(cache_file), ")")
      return(data)
    }
    message("[cache.R] No dept report cache found for ", dept_code)
    NULL
  }, error = function(e) {
    message("[cache.R] Error loading dept report cache: ", e$message)
    NULL
  })
}

# Clear dept report cache files. Pass dept_code to clear one dept, NULL for all.
# Also removes any orphaned .tmp files left by crashed writes.
clear_dept_report_cache <- function(dept_code = NULL) {
  cache_dir <- get_cache_dir()
  qs_pattern  <- if (is.null(dept_code)) "^dept_.*\\.qs$"  else paste0("^dept_", dept_code, "_.*\\.qs$")
  tmp_pattern <- if (is.null(dept_code)) "^dept_.*\\.tmp$" else paste0("^dept_", dept_code, "_.*\\.tmp$")
  cache_files <- c(
    list.files(cache_dir, pattern = qs_pattern,  full.names = TRUE),
    list.files(cache_dir, pattern = tmp_pattern, full.names = TRUE)
  )
  if (length(cache_files) > 0) {
    file.remove(cache_files)
    message("[cache.R] Cleared ", length(cache_files), " dept report cache file(s)")
  } else {
    message("[cache.R] No dept report cache files to clear")
  }
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
