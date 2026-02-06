#!/usr/bin/env Rscript
#
# Integration test for the full report generation pipeline
#
# Tests the complete flow: data → create_dept_report_data → create_report → file output
#
# Usage:
#   Rscript tests/test-report-pipeline.R
#   Rscript tests/test-report-pipeline.R --docker   # Simulate Docker mode

message("=== Report Pipeline Integration Test ===\n")

# Parse args
args <- commandArgs(trailingOnly = TRUE)
simulate_docker <- "--docker" %in% args

# Ensure we're in project root
if (basename(getwd()) == "tests") {
  setwd("..")
}

# Load libraries
suppressPackageStartupMessages({
  library(tidyverse)
  library(plotly)
  library(qs)
})

# Load config
config_file <- if (file.exists("config/config.R")) "config/config.R" else "config/shiny_config.R"
source(config_file)
message("Loaded config: ", config_file)

# Load functions
source("R/branches/load-funcs.R")
load_funcs(cedar_base_dir)

# Track test results
tests_passed <- 0
tests_failed <- 0

pass <- function(msg) {
  tests_passed <<- tests_passed + 1
  message("  PASS: ", msg)
}

fail <- function(msg) {
  tests_failed <<- tests_failed + 1
  message("  FAIL: ", msg)
}

# =============================================================================
# Test 1: Config paths are valid
# =============================================================================
message("\n=== Test 1: Config Paths ===")

message("  cedar_base_dir: ", cedar_base_dir)
message("  cedar_output_dir: ", cedar_output_dir)
message("  cedar_data_dir: ", cedar_data_dir)

# Check Rmd exists
rmd_path <- file.path(cedar_base_dir, "Rmd", "dept-report.Rmd")
if (file.exists(rmd_path)) {
  pass(paste0("Rmd file exists: ", rmd_path))
} else {
  fail(paste0("Rmd file missing: ", rmd_path))
}

# Check data dir exists
if (dir.exists(cedar_data_dir)) {
  pass(paste0("Data dir exists: ", cedar_data_dir))
} else {
  fail(paste0("Data dir missing: ", cedar_data_dir))
}

# =============================================================================
# Test 2: Load data
# =============================================================================
message("\n=== Test 2: Load Data ===")

data_objects <- list()

load_data <- function(name) {
  qs_path <- file.path(cedar_data_dir, paste0(name, ".qs"))
  rds_path <- file.path(cedar_data_dir, paste0(name, ".Rds"))
  
  if (file.exists(qs_path)) {
    return(qread(qs_path))
  } else if (file.exists(rds_path)) {
    return(readRDS(rds_path))
  }
  return(NULL)
}

for (name in c("cedar_programs", "cedar_degrees", "cedar_students", "cedar_faculty", "cedar_sections")) {
  data_objects[[name]] <- load_data(name)
  if (!is.null(data_objects[[name]])) {
    message("  ", name, ": ", nrow(data_objects[[name]]), " rows")
  } else {
    message("  ", name, ": not found")
  }
}

if (!is.null(data_objects$cedar_programs) && !is.null(data_objects$cedar_sections)) {
  pass("Required data loaded")
} else {
  fail("Missing required data (cedar_programs or cedar_sections)")
  stop("Cannot continue without data")
}

# =============================================================================
# Test 3: create_dept_report_data
# =============================================================================
message("\n=== Test 3: create_dept_report_data ===")

TEST_DEPT <- "HIST"
opt <- list(dept = TEST_DEPT, prog = NULL)

d_params <- tryCatch({
  create_dept_report_data(data_objects, opt)
}, error = function(e) {
  fail(paste0("create_dept_report_data error: ", e$message))
  NULL
})

if (!is.null(d_params) && d_params$dept_code == TEST_DEPT) {
  pass(paste0("Generated d_params for ", TEST_DEPT))
  message("    Tables: ", length(d_params$tables))
  message("    Plots: ", length(d_params$plots))
} else if (!is.null(d_params)) {
  fail("d_params has wrong dept_code")
}

# =============================================================================
# Test 4: create_report
# =============================================================================
if (!is.null(d_params)) {
  message("\n=== Test 4: create_report ===")
  
  # Use temp directory for output
  temp_output <- tempfile(pattern = "cedar-test-")
  dir.create(temp_output, recursive = TRUE)
  
  # Set up d_params
  d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "dept-report.Rmd")
  d_params$output_dir_base <- temp_output
  d_params$output_filename <- "TEST_REPORT"
  
  message("  rmd_file: ", d_params$rmd_file)
  message("  output_dir_base: ", d_params$output_dir_base)
  
  if (simulate_docker) {
    message("  Mode: Docker (simulated)")
    # Mock is_docker
    is_docker <- function() TRUE
    
    # In Docker mode, output goes to getwd()/data/
    docker_data_dir <- file.path(temp_output, "data")
    dir.create(docker_data_dir, recursive = TRUE)
    
    # Temporarily change working directory
    old_wd <- getwd()
    setwd(temp_output)
    
    expected_output <- file.path(temp_output, "data", "TEST_REPORT.html")
  } else {
    message("  Mode: CLI")
    expected_output <- file.path(temp_output, "html", "TEST_REPORT.html")
  }
  
  message("  Expected output: ", expected_output)
  
  result <- tryCatch({
    create_report(opt = list(dept = TEST_DEPT), d_params)
  }, error = function(e) {
    fail(paste0("create_report error: ", e$message))
    NULL
  })
  
  # Restore working directory if Docker mode
  if (simulate_docker) {
    setwd(old_wd)
  }
  
  if (!is.null(result)) {
    message("  Returned: ", result)
    
    if (file.exists(expected_output)) {
      size <- file.info(expected_output)$size
      pass(paste0("Report created (", size, " bytes)"))
    } else {
      fail(paste0("Report not found at: ", expected_output))
      
      # Debug: what files were created?
      all_files <- list.files(temp_output, recursive = TRUE)
      if (length(all_files) > 0) {
        message("  Files created: ", paste(all_files, collapse = ", "))
      }
    }
  }
  
  # Cleanup
  unlink(temp_output, recursive = TRUE)
}

# =============================================================================
# Summary
# =============================================================================
message("\n", paste(rep("=", 50), collapse = ""))
message("Tests passed: ", tests_passed)
message("Tests failed: ", tests_failed)

if (tests_failed == 0) {
  message("=== ALL TESTS PASSED ===")
} else {
  message("=== SOME TESTS FAILED ===")
}
message(paste(rep("=", 50), collapse = ""))
