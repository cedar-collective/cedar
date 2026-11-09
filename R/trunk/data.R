# this file provides miscellaneous functions used across CEDAR

# Data serialization wrapper functions to support both qs2 and RDS formats.
# These check the cedar_use_qs config flag and route to the appropriate format.
# NOTE: the binary engine is qs2 (the original `qs` package was archived from CRAN
# and superseded by qs2). The `.qs` file extension is retained — qs2 detects its
# format by file content, so filenames did not need to change. qs2 CANNOT read
# legacy `qs`-format files; all `.qs` data was re-encoded to qs2 at the cutover.

save_cedar_data <- function(data, filepath, use_qs = NULL) {
  # Check if we should use the binary (qs2) format
  if (is.null(use_qs)) {
    use_qs <- exists("cedar_use_qs") && isTRUE(cedar_use_qs)
  }

  if (use_qs && requireNamespace("qs2", quietly = TRUE)) {
    message("Saving data using qs2 format: ", filepath)
    qs2::qs_save(data, filepath)
  } else {
    if (use_qs) {
      message("QS package not available, falling back to RDS format")
    }
    message("[data.R] Saving data using RDS format: ", filepath)
    saveRDS(data, filepath)
  }
}

load_cedar_data <- function(filepath, use_qs = NULL) {
  # Check if we should use QS format (preference)
  if (is.null(use_qs)) {
    use_qs <- exists("cedar_use_qs") && isTRUE(cedar_use_qs)
  }
  
  # Detect actual file extension and use appropriate loader
  if (grepl("\\.qs$", filepath, ignore.case = TRUE)) {
    # File has .qs extension (qs2-format content)
    if (file.exists(filepath) && requireNamespace("qs2", quietly = TRUE)) {
      message("[data.R] Loading data using qs2 format: ", filepath)
      return(qs2::qs_read(filepath))
    } else if (!file.exists(filepath)) {
      # Try RDS fallback if QS file doesn't exist
      rds_path <- sub("\\.qs$", ".Rds", filepath)
      if (file.exists(rds_path)) {
        message("[data.R] QS file not found, loading RDS format: ", rds_path)
        return(readRDS(rds_path))
      }
    }
  } else if (grepl("\\.Rds$", filepath, ignore.case = TRUE)) {
    # File has .Rds extension
    if (file.exists(filepath)) {
      message("[data.R] Loading data using RDS format: ", filepath)
      return(readRDS(filepath))
    } else if (use_qs && requireNamespace("qs2", quietly = TRUE)) {
      # Try qs2 alternative if RDS file doesn't exist
      qs_path <- sub("\\.Rds$", ".qs", filepath)
      if (file.exists(qs_path)) {
        message("[data.R] RDS file not found, loading qs2 format: ", qs_path)
        return(qs2::qs_read(qs_path))
      }
    }
  }
  
  # No valid file found
  message("[data.R] No data file found at: ", filepath)
  return(tibble())
}


# Get the appropriate file extension based on config
get_data_extension <- function(use_qs = NULL) {
  message("[data.R] Welcome to get_data_extension!")
  if (is.null(use_qs)) {
    use_qs <- exists("cedar_use_qs") && isTRUE(cedar_use_qs)
  }
  message("[data.R] use_qs: ", use_qs)

  if (requireNamespace("qs2", quietly = TRUE)) {
    message("[data.R] qs2 package is available.")
  } else {
    message("[data.R] WARNING: qs2 package is NOT available; falling back to Rds.")
  }

  return(if (use_qs && requireNamespace("qs2", quietly = TRUE)) ".qs" else ".Rds")
}



# The file each table is saved in, where its name differs from the table's.
# Empty since 2026-11-09: the class list's file took the table's name
# (cedar_registrations.qs; ADR-001 step 5), and a loader still asks through
# cedar_table_file() so the next rename is one line here.
CEDAR_TABLE_FILES <- c()

cedar_table_file <- function(name) {
  if (name %in% names(CEDAR_TABLE_FILES)) CEDAR_TABLE_FILES[[name]] else name
}

#' Rename the class list's file from the table's old name, once
#'
#' Production's data directory was written by a transform that saved the
#' class list as cedar_students.qs (its name until ADR-001 step 5). The deploy
#' gate runs this before anything reads the file: the old file is renamed to
#' the table's name when no new one exists, and left alone, unread and
#' reported, when both exist. A data directory with neither is not this
#' function's concern (the staleness checks report it).
#'
#' @param data_dir The directory holding the saved tables.
#' @param ext The saved files' extension.
#' @return The files renamed (new paths), invisibly; character(0) when none.
migrate_class_list_file <- function(data_dir, ext = ".qs") {
  renamed <- character(0)
  for (suffix in c("", "_small")) {
    old <- file.path(data_dir, paste0("cedar_students", suffix, ext))
    new <- file.path(data_dir, paste0("cedar_registrations", suffix, ext))
    if (!file.exists(old)) next
    if (file.exists(new)) {
      message("[data.R] ", basename(old), " is not read: ", basename(new),
              " is the class list's file (ADR-001 step 5). Remove the old file.")
      next
    }
    if (!file.rename(old, new)) {
      stop("[data.R] could not rename ", old, " to ", new, call. = FALSE)
    }
    message("[data.R] Renamed ", basename(old), " to ", basename(new),
            ": the class list's file takes the table's name (ADR-001 step 5).")
    renamed <- c(renamed, new)
  }
  invisible(renamed)
}

# The measure tables (ADR-001 step 6). The transform builds them over the
# class list as the app loads it and saves them beside the fact tables; the
# app loads them and never builds one: a restart is a load. The hint is the
# command that builds them by hand; the deploy gate and the refresh run it.
CEDAR_MEASURE_TABLES <- c("cedar_attempts", "cedar_course_terms", "cedar_course_flows")
CEDAR_MEASURES_REBUILD_HINT <-
  "Rscript --vanilla R/data-parsers/transform-to-cedar.R --tables measures"

#' Load one saved measure table, or stop
#'
#' Fails closed on every way the saved table can disagree with what the app
#' loaded: missing; older than the class list it was counted over; built from
#' other mapping files (its units would be another file's); over another first
#' term (its course-code renames would be another window's); or, by the
#' table's own check, from another build, outcome policy, edge or set of
#' course codes. Nothing is rebuilt here.
#'
#' @param name One of CEDAR_MEASURE_TABLES.
#' @param data_dir The directory holding the saved tables.
#' @param class_list_path The saved class list's path, for the file-time check.
#' @param is_current The table's own currency check over the loaded tables
#'   (attempts_is_current(), course_terms_is_current(),
#'   course_flows_is_current()), as a function of the saved table.
#' @param dims_fingerprint cedar_dims_fingerprint() of the dimensions loaded.
#' @param min_term The first term the app loads (cedar_min_term).
#' @param ext The saved files' extension.
#' @return The saved table, attributes kept.
cedar_load_measure_table <- function(name, data_dir, class_list_path, is_current,
                                     dims_fingerprint, min_term, ext = get_data_extension()) {
  if (!name %in% CEDAR_MEASURE_TABLES) {
    stop("[data.R] cedar_load_measure_table(): ", name, " is not a measure table")
  }
  path <- file.path(data_dir, paste0(name, ext))
  refuse <- function(why) {
    stop("[data.R] ", name, " ", why, ". The app loads the measure tables and never ",
         "builds one (ADR-001 step 6): run `", CEDAR_MEASURES_REBUILD_HINT,
         "` (the deploy gate and the data refresh do) and start again.", call. = FALSE)
  }
  if (!file.exists(path)) refuse(paste0("has not been built (no ", path, ")"))
  if (!file.exists(class_list_path)) {
    stop("[data.R] cedar_load_measure_table(): no class list at ", class_list_path, call. = FALSE)
  }
  if (file.mtime(path) < file.mtime(class_list_path)) {
    refuse("is older than the class list it was counted over")
  }
  tbl <- if (ext == ".qs") qs2::qs_read(path) else readRDS(path)
  if (!identical(attr(tbl, "cedar_dims_fingerprint", exact = TRUE), dims_fingerprint)) {
    refuse("was built from other mapping files")
  }
  built_from <- attr(tbl, "cedar_min_term", exact = TRUE)
  if (!identical(as.integer(built_from), as.integer(min_term))) {
    refuse(sprintf("was built over terms from %s; this app starts at %s",
                   if (is.null(built_from)) "an unstamped first term" else built_from, min_term))
  }
  if (!isTRUE(is_current(tbl))) {
    refuse("is from another build, outcome policy, edge or set of course codes")
  }
  tbl
}

# Load CEDAR data model files (only supported model - no legacy fallbacks)
load_global_data <- function(opt) {
  message("[data.R] Loading CEDAR data model...")
  load_cedar_model_data(opt)
  message("[data.R] CEDAR data loading complete!")
}


# Load CEDAR data files
load_cedar_model_data <- function(opt) {
  # Define CEDAR files to load
  cedar_files <- c(
    "cedar_sections", "cedar_registrations", "cedar_student_terms",
    "cedar_programs", "cedar_degrees", "cedar_faculty", "cedar_applicants"
  )
  message("[data.R] cedar_files: ", paste(cedar_files, collapse=", "))

  # Helper function for timed loading with performance monitoring
  timed_load_datafile <- function(filename, label) {
    message(sprintf("[data.R] loading %s...", label))
    t <- system.time({ obj <- load_datafile(filename) })
    message(sprintf("[data.R] Loaded %s in %.2f seconds.", label, t["elapsed"]))
    obj
  }

  # Load all CEDAR files into a named list
  data_objects <- list()

  for (cedar_file in cedar_files) {
    data_objects[[cedar_file]] <- timed_load_datafile(cedar_table_file(cedar_file), cedar_file)
  }

  # Every loader attaches the unit columns from the mapping files (ADR-001
  # step 3): the saved tables carry keys only, as global.R, the cache-warming
  # scripts and cedar-repl.R all read them.
  cedar_dims <- build_cedar_dims()
  data_objects <- attach_default_units(data_objects, cedar_dims)
  data_objects[["cedar_dims"]] <- cedar_dims
  # The course dimension (ADR-001 step 4): one course_id per code, following the
  # confirmed successions in code_history.csv, attached to the sections and the
  # class lists beside subject_course. Never saved: a confirmed row changes it at
  # the next start, as a unit decision does.
  cedar_courses <- build_cedar_courses(data_objects[["cedar_sections"]], data_objects[["cedar_registrations"]], cedar_dims)
  data_objects <- attach_course_ids(data_objects, cedar_courses)
  data_objects[["cedar_courses"]] <- cedar_courses$courses
  data_objects[["cedar_course_codes"]] <- cedar_courses$codes

  # Map CEDAR tables to legacy variable names for backward compatibility
  # sections table contains course section data (includes enrollment counts)
  .GlobalEnv$sections <- data_objects[["cedar_sections"]]
  .GlobalEnv$courses <- data_objects[["cedar_sections"]]  # Alias for compatibility

  if (is.null(opt) || opt[["func"]] != "enrl") {
    # students table contains class lists (student enrollments in sections)
    .GlobalEnv$students <- data_objects[["cedar_registrations"]]
    .GlobalEnv$cedar_student_terms <- data_objects[["cedar_student_terms"]]
    .GlobalEnv$programs <- data_objects[["cedar_programs"]]
    .GlobalEnv$degrees <- data_objects[["cedar_degrees"]]
    .GlobalEnv$faculty <- data_objects[["cedar_faculty"]]
    .GlobalEnv$fac_by_term <- data_objects[["cedar_faculty"]]  # Alias for compatibility
    .GlobalEnv$applicants <- data_objects[["cedar_applicants"]]

  }

  # Make the data_objects list available globally
  .GlobalEnv$data_objects <- data_objects
}


load_datafile <- function(filename) {
  message("loading data for: ", filename,"...")
  

# Use small data file if config says so and file exists
  use_small <- exists("cedar_use_small_data") && isTRUE(cedar_use_small_data)
  small_filename <- paste0(filename, "_small")
  
  if (use_small) {
    ext <- get_data_extension()
    localfile <- file.path(cedar_data_dir, paste0(small_filename, ext))
    message("[data.R] Looking for small data file: ", localfile)
    if (file.exists(localfile)) {
      data <- load_cedar_data(localfile)
      message("[data.R] Loaded small data file.")
      return(data)
    } else {
      message("[data.R] Small data file not found! Loading regular file...")
    }
  }

    message("[data.R] Getting data from local file...")
    ext <- get_data_extension()
    localfile <- file.path(cedar_data_dir, paste0(filename, ext))
    message("[data.R] looking for: ", localfile,"...")
    data <- load_cedar_data(localfile)
  
  message("[data.R] Returning data with ", nrow(data), " rows.")
  return(data)
}


# check for expected data files and report number of records per term and last updated date

get_data_status <- function (data_objects) {
  
  message("[data.R] Welcome to get_data_status!")
  
  students <- data_objects[["cedar_registrations"]]
  courses <- data_objects[["cedar_sections"]]
  academic_studies <- data_objects[["cedar_programs"]]
  degrees <- data_objects[["cedar_degrees"]]
  cedar_faculty <- data_objects[["cedar_faculty"]]
  cedar_applicants <- data_objects[["cedar_applicants"]]

  # Initialize data_status tibble to return
  data_status <- tibble(
    dataset = character(),
    rows = numeric(),
    unique_terms = numeric(),
    last_3_terms = character(),
    as_of_date = character()
  )
  
  # Helper function to extract dataset stats
  get_dataset_stats <- function(data, dataset_name) {
    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }
    
    # Validate CEDAR required columns
    required_cols <- c("term", "as_of_date")
    missing_cols <- setdiff(required_cols, colnames(data))
    
    if (length(missing_cols) > 0) {
      stop("[data.R] ", dataset_name, " is missing required CEDAR columns: ",
           paste(missing_cols, collapse = ", "),
           "\n  as_of_date tracks when data was downloaded from MyReports and transformed to CEDAR format",
           "\n  Found columns: ", paste(colnames(data), collapse = ", "))
    }
    
    # Get term column (CEDAR uses lowercase 'term')
    unique_terms <- n_distinct(data[["term"]])
    all_terms <- sort(unique(data[["term"]]), decreasing = TRUE)
    last_3_terms <- head(all_terms, 3)
    last_3_terms_str <- paste(last_3_terms, collapse = ", ")
    
    # Get as_of_date (required CEDAR column - tracks data freshness)
    as_of_date <- max(data[["as_of_date"]], na.rm = TRUE)
    as_of_date <- as.character(as_of_date)

    # Compute last updated date per each of the last 3 terms
    last_3_term_updates <- sapply(last_3_terms, function(term_val) {
      term_data <- data[data[["term"]] == term_val, , drop = FALSE]
      term_date <- max(term_data[["as_of_date"]], na.rm = TRUE)
      paste0(term_val, ": ", as.character(term_date))
    })
    last_3_term_updates_str <- paste(last_3_term_updates, collapse = "; ")
    
    tibble(
      dataset = dataset_name,
      rows = nrow(data),
      unique_terms = unique_terms,
      last_3_terms = last_3_terms_str,
      as_of_date = as_of_date,
      last_3_term_updates = last_3_term_updates_str
    )
  }
  
  # Gather stats for each dataset
  if (!is.null(students)) {
    message("getting cedar_registrations status...")
    stats <- get_dataset_stats(students, "cedar_registrations")
    if (!is.null(stats)) data_status <- rbind(data_status, stats)
  }

  if (!is.null(courses)) {
    message("getting cedar_sections status...")
    stats <- get_dataset_stats(courses, "cedar_sections")
    if (!is.null(stats)) data_status <- rbind(data_status, stats)
  }
  
  if (!is.null(academic_studies)) {
    message("getting cedar_programs status...")
    stats <- get_dataset_stats(academic_studies, "cedar_programs")
    if (!is.null(stats)) data_status <- rbind(data_status, stats)
  }
  
  if (!is.null(degrees)) {
    message("getting cedar_degrees status...")
    stats <- get_dataset_stats(degrees, "cedar_degrees")
    if (!is.null(stats)) data_status <- rbind(data_status, stats)
  }

  if (!is.null(cedar_faculty)) {
    message("getting cedar_faculty status...")
    stats <- get_dataset_stats(cedar_faculty, "cedar_faculty")
    if (!is.null(stats)) data_status <- rbind(data_status, stats)
  }

  if (!is.null(cedar_applicants)) {
    message("getting cedar_applicants status...")
    stats <- get_dataset_stats(cedar_applicants, "cedar_applicants")
    if (!is.null(stats)) data_status <- rbind(data_status, stats)
  }

  message("[data.R] Completed data status summary with ", nrow(data_status), " datasets")
  return(data_status)
}
