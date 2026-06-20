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
    "cedar_sections", "cedar_students", "cedar_student_term_credits",
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
    data_objects[[cedar_file]] <- timed_load_datafile(cedar_file, cedar_file)
  }

  # Map CEDAR tables to legacy variable names for backward compatibility
  # sections table contains course section data (includes enrollment counts)
  .GlobalEnv$sections <- data_objects[["cedar_sections"]]
  .GlobalEnv$courses <- data_objects[["cedar_sections"]]  # Alias for compatibility

  if (is.null(opt) || opt[["func"]] != "enrl") {
    # students table contains class lists (student enrollments in sections)
    .GlobalEnv$students <- data_objects[["cedar_students"]]
    .GlobalEnv$cedar_student_term_credits <- data_objects[["cedar_student_term_credits"]]
    .GlobalEnv$student_term_credits <- data_objects[["cedar_student_term_credits"]]
    .GlobalEnv$programs <- data_objects[["cedar_programs"]]
    .GlobalEnv$degrees <- data_objects[["cedar_degrees"]]
    .GlobalEnv$faculty <- data_objects[["cedar_faculty"]]
    .GlobalEnv$fac_by_term <- data_objects[["cedar_faculty"]]  # Alias for compatibility
    .GlobalEnv$applicants <- data_objects[["cedar_applicants"]]

    # Load forecasts if they exist
    if (file.exists(file.path(cedar_data_dir, paste0("forecasts", get_data_extension())))) {
      .GlobalEnv$forecasts <- timed_load_datafile("forecasts", "forecasts")
      data_objects[["forecasts"]] <- .GlobalEnv$forecasts
    }
  }

  # Make the data_objects list available globally
  .GlobalEnv$data_objects <- data_objects
}


load_datafile <- function(filename) {
  message("loading data for: ", filename,"...")
  

  # new forecasts can get saved at any time
  if (filename == "forecasts") {
    message("loading forecast data...")
    
  if (is_docker()) {
    # if running in Docker, load forecasts from container data directory
    # TODO: see if this can be relative path to ./data
    message("running in Docker; loading forecasts from /srv/shiny-server/cedar/data/ ...")
    ext <- get_data_extension()
    forecast_file <- file.path("/srv/shiny-server/cedar/data/", paste0("forecasts", ext))
    data <- load_cedar_data(forecast_file)
    return(data)
  } else if (as.logical(Sys.getenv("shiny"))) {
    # if in shiny context load (temp) forecasts from root directory
    message("trying to load forecasts in Shiny...")
    ext <- get_data_extension()
    forecast_file <- paste0("forecasts", ext)
    data <- load_cedar_data(forecast_file)
    return(data)
  }
  } # end if filename == "forecasts"


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
  
  students <- data_objects[["cedar_students"]]
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
    message("getting cedar_students status...")
    stats <- get_dataset_stats(students, "cedar_students")
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
