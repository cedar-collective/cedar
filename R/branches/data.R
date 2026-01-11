# this file provides miscellaneous functions used across CEDAR

# Data serialization wrapper functions to support both QS and RDS formats
# These functions check the cedar_use_qs config flag and route to the appropriate format

save_cedar_data <- function(data, filepath, use_qs = NULL) {
  # Check if we should use QS format
  if (is.null(use_qs)) {
    use_qs <- exists("cedar_use_qs") && isTRUE(cedar_use_qs)
  }
  
  if (use_qs && requireNamespace("qs", quietly = TRUE)) {
    message("Saving data using QS format: ", filepath)
    qs::qsave(data, filepath, preset = "fast")
  } else {
    if (use_qs) {
      message("QS package not available, falling back to RDS format")
    }
    message("Saving data using RDS format: ", filepath)
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
    # File has .qs extension
    if (file.exists(filepath) && requireNamespace("qs", quietly = TRUE)) {
      message("Loading data using QS format: ", filepath)
      return(qs::qread(filepath))
    } else if (!file.exists(filepath)) {
      # Try RDS fallback if QS file doesn't exist
      rds_path <- sub("\\.qs$", ".Rds", filepath)
      if (file.exists(rds_path)) {
        message("QS file not found, loading RDS format: ", rds_path)
        return(readRDS(rds_path))
      }
    }
  } else if (grepl("\\.Rds$", filepath, ignore.case = TRUE)) {
    # File has .Rds extension
    if (file.exists(filepath)) {
      message("Loading data using RDS format: ", filepath)
      return(readRDS(filepath))
    } else if (use_qs && requireNamespace("qs", quietly = TRUE)) {
      # Try QS alternative if RDS file doesn't exist
      qs_path <- sub("\\.Rds$", ".qs", filepath)
      if (file.exists(qs_path)) {
        message("RDS file not found, loading QS format: ", qs_path)
        return(qs::qread(qs_path))
      }
    }
  }
  
  # No valid file found
  message("No data file found at: ", filepath)
  return(tibble())
}


# Get the appropriate file extension based on config
get_data_extension <- function(use_qs = NULL) {
  message("[data.R] Welcome to get_data_extension!")
  if (is.null(use_qs)) {
    use_qs <- exists("cedar_use_qs") && isTRUE(cedar_use_qs)
  }
  message("[data.R] use_qs: ", use_qs)

  if (requireNamespace("qs", quietly = TRUE)) {
    message("[data.R] qs package is available.")
  } else {
    message("[data.R] WARNING: qs package is NOT available; falling back to Rds.")
  }
  
  return(if (use_qs && requireNamespace("qs", quietly = TRUE)) ".qs" else ".Rds")
}



# load global data files
load_global_data <- function(opt) {
  message("[data.R] Welcome to load_global_data!")

  # Check if we should use the new CEDAR data model (default: FALSE for backward compatibility)
  use_cedar_model <- exists("cedar_use_new_model") && isTRUE(cedar_use_new_model)

  if (use_cedar_model) {
    message("[data.R] Using NEW CEDAR data model")
    load_cedar_model_data(opt)
  } else {
    message("[data.R] Using legacy MyReports data format")
    load_legacy_data(opt)
  }

  message("[data.R] global data loading complete!")
}


# Load legacy MyReports-format data (original behavior)
load_legacy_data <- function(opt) {
  # Define core data files to load
  file_list <- c("DESRs", "class_lists", "academic_studies", "degrees", "hr_data")
  message("[data.R] file_list: ", paste(file_list, collapse=", "))

  # Helper function for timed loading with performance monitoring
  timed_load_datafile <- function(filename, label) {
    message(sprintf("loading %s...", label))
    t <- system.time({ obj <- load_datafile(filename) })
    message(sprintf("Loaded %s in %.2f seconds.", label, t["elapsed"]))
    obj
  }

  # Load all files into a named list
  data_objects <- list()
  filename_map <- list(
    "DESRs" = "desrs",
    "class_lists" = "class_lists",
    "academic_studies" = "academic_studies",
    "degrees" = "degrees",
    "hr_data" = "hr_data",
    "forecasts" = "forecasts"
  )

  for (base_name in file_list) {
    filename <- filename_map[[base_name]]
    data_objects[[base_name]] <- timed_load_datafile(filename, base_name)
  }

  # Extract individual objects for backward compatibility and convenience
  .GlobalEnv$courses <- data_objects[["DESRs"]]

  if (is.null(opt) || opt[["func"]] != "enrl") {
    .GlobalEnv$students <- data_objects[["class_lists"]]
    .GlobalEnv$academic_studies <- data_objects[["academic_studies"]]
    .GlobalEnv$degrees <- data_objects[["degrees"]]
    .GlobalEnv$fac_by_term <- data_objects[["hr_data"]]
    if ("forecasts" %in% names(data_objects)) {
      .GlobalEnv$forecasts <- data_objects[["forecasts"]]
    }
  }

  # Also make the data_objects list available globally for modern access patterns
  .GlobalEnv$data_objects <- data_objects
}


# Load new CEDAR data model files
load_cedar_model_data <- function(opt) {
  # Define CEDAR model files to load
  cedar_files <- c("cedar_sections", "cedar_enrollments", "cedar_programs", "cedar_degrees", "cedar_faculty")
  message("[data.R] cedar_files: ", paste(cedar_files, collapse=", "))

  # Helper function for timed loading with performance monitoring
  timed_load_datafile <- function(filename, label) {
    message(sprintf("loading %s...", label))
    t <- system.time({ obj <- load_datafile(filename) })
    message(sprintf("Loaded %s in %.2f seconds.", label, t["elapsed"]))
    obj
  }

  # Load all CEDAR files into a named list
  data_objects <- list()

  for (cedar_file in cedar_files) {
    data_objects[[cedar_file]] <- timed_load_datafile(cedar_file, cedar_file)
  }

  # Map CEDAR tables to legacy variable names for backward compatibility
  # This allows existing code to continue working without changes
  .GlobalEnv$sections <- data_objects[["cedar_sections"]]
  .GlobalEnv$courses <- data_objects[["cedar_sections"]]  # Alias for compatibility

  if (is.null(opt) || opt[["func"]] != "enrl") {
    .GlobalEnv$enrollments <- data_objects[["cedar_enrollments"]]
    .GlobalEnv$students <- data_objects[["cedar_enrollments"]]  # Alias for compatibility
    .GlobalEnv$programs <- data_objects[["cedar_programs"]]
    .GlobalEnv$degrees <- data_objects[["cedar_degrees"]]
    .GlobalEnv$faculty <- data_objects[["cedar_faculty"]]
    .GlobalEnv$fac_by_term <- data_objects[["cedar_faculty"]]  # Alias for compatibility

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
  

  # forecasting data is weird because it new forecasts can get saved at any time
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
    # if running in Posit Connect, load (temp) forecasts from root directory
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
      message("[data.R] Small data file not found, loading regular file.")
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
  
  message("Welcome to get_data_status!")
  
  students <- data_objects[["class_lists"]]
  courses <- data_objects[["DESRs"]]
  academic_studies <- data_objects[["academic_studies"]]
  degrees <- data_objects[["degrees"]]
  hr_data <- data_objects[["hr_data"]]

  # initialize data_status tibble to return
  data_status <- tibble(
    MyReport = character(),
    Term = character(),
    Last_Updated = character(),
    Num_Rows = numeric()
  )
  
  # helper function to normalize summary data since they have different fields for term
  normalize_summary <- function(list_name, term_col, summary, data_status) {
    summary <- summary %>% 
      rename(`Term` = !!term_col, 
             `Last_Updated` = as_of_date, 
             `Num_Rows` = rows)
    
    summary <- summary %>% add_column(MyReport = list_name, .before = "Term")
    
    data_status <- rbind(data_status, summary)
    
    return(data_status)
  }
  
  
  message("getting class list status...")
  if (!is.null(students)) {
    summary_status <- students %>% group_by(`Academic Period Code`,as_of_date) %>% summarize (rows = n(), .groups="keep")
    data_status <- normalize_summary("class_list", "Academic Period Code", summary_status, data_status)
  } else {
    message("No students data provided.")
  }

  message("getting DESRs status...")
  if (!is.null(courses)) {
    summary_status <- courses %>% group_by(`TERM`,as_of_date) %>% summarize (rows = n(), .groups="keep")
    data_status <- normalize_summary("DESR", "TERM", summary_status, data_status)
  } else {
    message("No courses data provided.")
  }
  
  
  message("getting academic study status...")
  if (!is.null(academic_studies)) {
    # academic_studies <- load_academic_studies()
    summary_status <- academic_studies %>% group_by(term_code ,as_of_date) %>% summarize (rows = n(), .groups="keep")
    data_status <- normalize_summary("academic_study", "term_code", summary_status, data_status)
  } else {
    message("No academic studies data provided.")
  }
  
  
  message("getting degrees status...")
  if (!is.null(degrees)) {
    # degrees <- load_degrees()
    summary_status <- degrees %>% group_by(`Academic Period Code`,as_of_date) %>% summarize (rows = n(), .groups="keep")
    data_status <- normalize_summary("degree", "Academic Period Code", summary_status, data_status)
  } else {
    message("No degrees data provided.")
  }

  message("getting HR Report status:")
  message("TODO: fix this.")
  # if (!is.null(hr_data)) {
  #   summary_status <- hr_data %>% group_by(as_of_date) %>% summarize (rows = n())
  #   summary_status <- summary_status %>% add_column(`Academic Period Code` = "202510", .before = "as_of_date")
  #   data_status <- normalize_summary("hr_data", "Academic Period Code", summary_status, data_status)
  # } else {
  #   message("No HR data provided.")
  # }
  
  return(data_status)
}
