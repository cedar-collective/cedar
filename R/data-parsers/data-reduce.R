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

cedar_data_docker_dir <- "/Users/fwgibbs/Dropbox/projects/shared-data"

file_specs <- list(
  students = list(file = "class_lists", term_col = "Academic Period Code"),
  courses = list(file = "DESRs", term_col = "TERM"),
  academic_studies = list(file = "academic_studies", term_col = "term_code"),
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
    data_small <- data[data[[spec$term_col]] >= "202380", ]
    message("Filtered from ", nrow(data), " to ", nrow(data_small), " rows (term >= 202380)")
  } else {
    message("Term column not found in data: ", spec$term_col)
    data_small <- data
  }
  
  message("Saving dataset: ", spec$file, " with term column: ", spec$term_col)
  save_data_file(data_small, cedar_data_docker_dir, spec$file, result$format)
}
