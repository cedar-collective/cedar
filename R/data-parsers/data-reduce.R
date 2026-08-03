# data-reduce.R
# 
# This script reduces the size of CEDAR datasets by filtering based on a specific term code.
# It automatically detects and processes both RDS and QS format files, maintaining the 
# source format for output files.
#
# Purpose:
#   Create smaller data files for testing, development, or sharing without exposing 
#   full historical data. Particularly useful for:
#   - Docker container deployments with size constraints
#   - Development/testing environments
#   - Sharing sample data with collaborators
#
# Behavior:
#   - Searches for data files in both .qs and .Rds formats
#   - Prioritizes .qs files if both formats exist (faster I/O)
#   - Filters data to include only recent terms (>= 202380 by default)
#   - Saves reduced files with "_small" suffix in the same format as source
#   - Preserves original files (non-destructive)
#
# Usage (from CEDAR root folder):
#   Rscript scripts/data-reduce.R
##
#   # Results:
#   #   DESRs.qs (150MB, 500k rows) → DESRs_small.qs (15MB, 50k rows)
#   #   class_lists.Rds (200MB) → class_lists_small.Rds (20MB)
#
# Configuration:
#   - cedar_data_docker_dir: Directory containing full data files
#   - file_specs: List of files to process with their term column names
#   - Term filter: Currently set to >= "202380" (Fall 2023 onwards)
#
# Requirements:
#   - dplyr package (required)
#   - qs package (optional, for .qs file support)
#
# Output:
#   Creates *_small.qs or *_small.Rds files in the same directory as source files

# Load required libraries
library(dplyr)
if (requireNamespace("qs2", quietly = TRUE)) {
  library(qs2)
  message("qs2 package loaded for faster I/O")
}

# academic_period_to_term() — this script runs standalone under Rscript, so it
# does not get the environment load_funcs() would normally set up. Fail loudly
# rather than proceeding without the term converter, which would put the
# Academic Period filter back into the silent-empty state this replaced.
if (!exists("academic_period_to_term")) {
  utils_path <- Filter(file.exists,
                       c("R/trunk/utils.R", "../trunk/utils.R", "../../R/trunk/utils.R"))
  if (length(utils_path) == 0) {
    stop("[data-reduce.R] Cannot find R/trunk/utils.R for academic_period_to_term(). ",
         "Run this from the project root.")
  }
  source(utils_path[1])
}

cedar_data_docker_dir <- "/Users/fwgibbs/Dropbox/projects/shared-data"

file_specs <- list(
  students = list(file = "class_lists", term_col = "Academic Period Code"),
  courses = list(file = "DESRs", term_col = "TERM"),
  # "Academic Period", not "term_code". The parsed academic_studies file carries
  # a term_code column that is all-NA for recent pulls — transform-to-cedar.R
  # re-derives it from Academic Period and never reads the stale one, so the
  # main pipeline is unaffected, but keying this script on it silently filtered
  # every row out. Academic Period is the field MyReports actually populates.
  academic_studies = list(file = "academic_studies", term_col = "Academic Period"),
  degrees = list(file = "degrees", term_col = "Academic Period Code")
  #fac_by_term = list(file = "fac_by_term", term_col = "Academic Period")
)

# Helper function to find and load data file (tries .qs first, then .Rds)
load_data_file <- function(base_path, filename) {
  qs_path <- file.path(base_path, paste0(filename, ".qs"))
  rds_path <- file.path(base_path, paste0(filename, ".Rds"))
  
  if (file.exists(qs_path) && requireNamespace("qs2", quietly = TRUE)) {
    message("Loading qs2 format: ", qs_path)
    return(list(data = qs2::qs_read(qs_path), format = "qs", path = qs_path))
  } else if (file.exists(rds_path)) {
    message("Loading RDS format: ", rds_path)
    return(list(data = readRDS(rds_path), format = "rds", path = rds_path))
  } else {
    return(NULL)
  }
}

# Helper function to save data file in same format as source
save_data_file <- function(data, base_path, filename, format) {
  if (format == "qs" && requireNamespace("qs2", quietly = TRUE)) {
    out_path <- file.path(base_path, paste0(filename, "_small.qs"))
    message("Saving qs2 format: ", out_path)
    qs2::qs_save(data, out_path)
  } else {
    out_path <- file.path(base_path, paste0(filename, "_small.Rds"))
    message("Saving RDS format: ", out_path)
    saveRDS(data, out_path)
  }
}

for (spec in file_specs) {
  result <- load_data_file(cedar_data_docker_dir, spec$file)
  
  if (is.null(result)) {
    message("File not found: ", spec$file, " (tried .qs and .Rds)")
    next
  }
  
  message("Processing file: ", result$path)
  data <- result$data
  
  # Only filter if term_col exists in the data
  if (spec$term_col %in% names(data)) {
    # Normalise to an integer term code before comparing. "Academic Period"
    # holds labels ("Fall 2023"), not codes, and a string comparison against
    # "202380" silently keeps or drops everything depending on the label.
    raw   <- data[[spec$term_col]]
    terms <- if (identical(spec$term_col, "Academic Period")) {
      academic_period_to_term(raw)
    } else {
      suppressWarnings(as.integer(raw))
    }

    if (all(is.na(terms))) {
      stop("[data-reduce.R] Term column '", spec$term_col, "' in ", spec$file,
           " produced no usable term codes. Filtering on it would silently ",
           "empty the file. Sample values: ",
           paste(utils::head(unique(raw), 3), collapse = " | "))
    }

    keep <- !is.na(terms) & terms >= 202380L
    data_small <- data[keep, ]
    message("Filtered from ", nrow(data), " to ", nrow(data_small),
            " rows (term >= 202380); ", sum(is.na(terms)), " rows had no term code")
  } else {
    message("Term column not found in data: ", spec$term_col)
    data_small <- data
  }
  
  message("Saving dataset: ", spec$file, " with term column: ", spec$term_col)
  save_data_file(data_small, cedar_data_docker_dir, spec$file, result$format)
}
