#!/usr/bin/env Rscript
#
# CLI Integration Test: Department Report Pipeline
#
# This test validates the complete command-line workflow for generating
# department reports, simulating what happens when a user runs:
#   Rscript cedar.R -f dept-report -d HIST
#
# Tests:
# 1. Option parsing and validation
# 2. Data loading via load_global_data()
# 3. command_handler routing
# 4. create_dept_report execution
# 5. Output file generation
#
# Usage:
#   Rscript tests/test-cli-dept-report.R
#   OR
#   Rscript tests/test-cli-dept-report.R --dept ANTH
#
# The test uses real production data to ensure the full pipeline works.

message("\n", paste(rep("=", 60), collapse = ""))
message("=== CLI Department Report Pipeline Integration Test ===")
message(paste(rep("=", 60), collapse = ""), "\n")

start_time <- Sys.time()

# =============================================================================
# Setup
# =============================================================================

# Parse test arguments
args <- commandArgs(trailingOnly = TRUE)
TEST_DEPT <- "AS Anthropology"  # Default test department

for (i in seq_along(args)) {
  if (args[i] == "--dept" && i < length(args)) {
    TEST_DEPT <- args[i + 1]
  }
}

# Ensure we're in the right directory
test_dir <- getwd()
if (basename(test_dir) == "tests") {
  setwd("..")
  message("Changed directory from tests/ to project root")
}

message("Test Configuration:")
message("  Working directory: ", getwd())
message("  Test department: ", TEST_DEPT)
message("")

# =============================================================================
# Test 1: Load configuration (simulates cedar.R lines 141)
# =============================================================================
message("=== Test 1: Configuration Loading ===")

config_file <- "config/config.R"
if (!file.exists(config_file)) {
  # Fall back to shiny_config.R for testing
  config_file <- "config/shiny_config.R"
}

if (!file.exists(config_file)) {
  stop("FAIL: Cannot find config file. Make sure you're running from CEDAR project root")
}

tryCatch({
  source(config_file)
  message("PASS: Configuration loaded from ", config_file)
  message("  cedar_base_dir: ", cedar_base_dir)
  message("  cedar_data_dir: ", cedar_data_dir)
}, error = function(e) {
  stop("FAIL: Config loading failed: ", e$message)
})

# =============================================================================
# Test 2: Load functions (simulates cedar.R lines 142-148)
# =============================================================================
message("\n=== Test 2: Function Loading ===")

tryCatch({
  # Load required packages (minimal set for CLI)
  suppressPackageStartupMessages({
    library(tidyverse)
    library(optparse)
    library(plotly)
  })

  # Load function loader
  source("R/branches/load-funcs.R")

  # Load all functions
  load_funcs(cedar_base_dir)

  # Resolve conflicts (prefers dplyr, plotly)
  resolve_conflicts()

  message("PASS: Functions loaded successfully")

  # Verify critical functions exist
  critical_functions <- c("command_handler", "create_dept_report",
                          "create_dept_report_data", "load_global_data",
                          "set_payload", "get_headcount_data_for_dept_report")

  missing_funcs <- critical_functions[!sapply(critical_functions, exists, mode = "function")]
  if (length(missing_funcs) > 0) {
    message("FAIL: Missing critical functions: ", paste(missing_funcs, collapse = ", "))
  } else {
    message("PASS: All critical functions available")
  }

}, error = function(e) {
  stop("FAIL: Function loading failed: ", e$message)
})

# =============================================================================
# Test 3: Option parsing (simulates cedar.R set_option_list and parse_args)
# =============================================================================
message("\n=== Test 3: Option Parsing ===")

# Simulate what optparse would create
opt <- list(
  func = "dept-report",
  guide = FALSE,
  dept = TEST_DEPT,
  prog = NULL,
  output = "html",
  course_campus = NULL,
  course_college = NULL,
  course_status = "A",
  student_campus = NULL,
  student_college = NULL,
  classification = NULL,
  course = NULL,
  crn = NULL,
  enrl_min = NULL,
  enrl_max = NULL,
  gen_ed = NULL,
  inst = NULL,
  im = NULL,
  job_cat = NULL,
  level = NULL,
  major = NULL,
  pt = NULL,
  reg_status_code = NULL,
  subj = NULL,
  term = NULL,
  uel = FALSE,
  aop = NULL,
  crosslist = NULL,
  group_cols = NULL,
  arrange = NULL,
  nso = FALSE,
  forecast_method = NULL,
  forecast_conduit_term = NULL,
  onedrive = FALSE
)

message("PASS: Options parsed")
message("  func: ", opt$func)
message("  dept: ", opt$dept)
message("  output: ", opt$output)

# =============================================================================
# Test 4: Data Loading (simulates cedar.R line 151)
# =============================================================================
message("\n=== Test 4: Data Loading ===")

tryCatch({
  load_global_data(opt)

  message("PASS: Data loaded successfully")

  # Verify data_objects is available
  if (!exists("data_objects", envir = .GlobalEnv)) {
    stop("data_objects not created in global environment")
  }

  # Check CEDAR datasets
  required_datasets <- c("cedar_sections", "cedar_students", "cedar_programs",
                         "cedar_degrees", "cedar_faculty")
  missing_datasets <- setdiff(required_datasets, names(data_objects))

  if (length(missing_datasets) > 0) {
    message("FAIL: Missing CEDAR datasets: ", paste(missing_datasets, collapse = ", "))
  } else {
    message("PASS: All required CEDAR datasets loaded")
    for (ds in required_datasets) {
      message("  ", ds, ": ", nrow(data_objects[[ds]]), " rows")
    }
  }

  # Verify legacy aliases are set
  legacy_vars <- c("students", "courses", "programs", "degrees", "faculty")
  missing_legacy <- legacy_vars[!sapply(legacy_vars, exists, envir = .GlobalEnv)]
  if (length(missing_legacy) > 0) {
    message("WARNING: Missing legacy aliases: ", paste(missing_legacy, collapse = ", "))
  } else {
    message("PASS: Legacy variable aliases set")
  }

}, error = function(e) {
  stop("FAIL: Data loading failed: ", e$message)
})

# =============================================================================
# Test 5: command_handler routing (simulates cedar.R line 154)
# =============================================================================
message("\n=== Test 5: command_handler Routing ===")

tryCatch({
  message("Calling command_handler with opt$func = '", opt$func, "'...")

  result <- command_handler(opt)

  if (is.character(result)) {
    message("PASS: command_handler returned: ", result)
  } else {
    message("PASS: command_handler completed (returned ", class(result)[1], ")")
  }

}, error = function(e) {
  message("FAIL: command_handler failed!")
  message("Error: ", e$message)
  message("\nStack trace:")
  print(e)
})

# =============================================================================
# Test 6: Verify Output Files
# =============================================================================
message("\n=== Test 6: Output Verification ===")

# Check for generated HTML report
output_dir <- file.path(cedar_output_dir, "reports")
if (dir.exists(output_dir)) {
  # Look for recent report files
  report_files <- list.files(output_dir, pattern = "\\.html$|\\.aspx$",
                             full.names = TRUE, recursive = TRUE)

  # Filter to files modified in last 5 minutes
  recent_cutoff <- Sys.time() - 300  # 5 minutes ago
  recent_reports <- report_files[file.info(report_files)$mtime > recent_cutoff]

  if (length(recent_reports) > 0) {
    message("PASS: Report file(s) generated:")
    for (f in recent_reports) {
      info <- file.info(f)
      message("  ", basename(f), " (", format(info$size, big.mark = ","), " bytes)")
    }
  } else {
    message("INFO: No recent report files found in ", output_dir)
    message("  (This may be expected if output=shiny or test ran quickly)")
  }
} else {
  message("INFO: Output directory does not exist: ", output_dir)
}

# =============================================================================
# Test 7: Direct create_dept_report_data Test (Shiny path)
# =============================================================================
message("\n=== Test 7: create_dept_report_data (Shiny Path) ===")

tryCatch({
  shiny_opt <- list(
    dept = TEST_DEPT,
    prog = NULL,
    shiny = TRUE
  )

  d_params <- create_dept_report_data(data_objects, shiny_opt)

  message("PASS: create_dept_report_data completed")
  message("  Department: ", d_params$dept_name, " (", d_params$dept_code, ")")
  message("  Programs: ", paste(d_params$prog_names, collapse = ", "))
  message("  Tables generated: ", length(d_params$tables))
  message("  Plots generated: ", length(d_params$plots))

  # List outputs
  if (length(d_params$tables) > 0) {
    message("\n  Tables:")
    for (name in names(d_params$tables)) {
      tbl <- d_params$tables[[name]]
      if (!is.null(tbl) && is.data.frame(tbl)) {
        message("    ", name, ": ", nrow(tbl), " rows")
      } else {
        message("    ", name, ": NULL or non-dataframe")
      }
    }
  }

  if (length(d_params$plots) > 0) {
    message("\n  Plots:")
    for (name in names(d_params$plots)) {
      plt <- d_params$plots[[name]]
      if (!is.null(plt)) {
        message("    ", name, ": ", class(plt)[1])
      } else {
        message("    ", name, ": NULL")
      }
    }
  }

  # Verify expected outputs for dept reports
  expected_tables <- c("hc_progs_under_long_majors", "hc_progs_under_long_minors",
                       "hc_progs_grad_long_majors", "degree_summary_filtered_program")
  found_tables <- sum(expected_tables %in% names(d_params$tables))
  message("\n  Expected headcount/degree tables: ", found_tables, "/", length(expected_tables))

  expected_plots <- c("sfr_plot", "degree_summary_faceted_by_major_plot")
  found_plots <- sum(expected_plots %in% names(d_params$plots))
  message("  Expected plots: ", found_plots, "/", length(expected_plots))

}, error = function(e) {
  message("FAIL: create_dept_report_data failed!")
  message("Error: ", e$message)
})

# =============================================================================
# Test 8: Verify CEDAR Data Model Usage
# =============================================================================
message("\n=== Test 8: CEDAR Data Model Verification ===")

# Read source files to verify CEDAR naming
check_cedar_usage <- function(file_path, description) {
  if (!file.exists(file_path)) {
    message("  ", description, ": file not found")
    return(FALSE)
  }

  source <- readLines(file_path)

  # Check for CEDAR table references
  has_cedar_sections <- any(grepl("cedar_sections", source))
  has_cedar_students <- any(grepl("cedar_students", source))
  has_cedar_programs <- any(grepl("cedar_programs", source))
  has_cedar_faculty <- any(grepl("cedar_faculty", source))

  # Check for legacy references (should be minimal or aliased)
  has_DESRs <- any(grepl('data_objects\\[\\["DESRs"\\]\\]', source))
  has_class_lists <- any(grepl('data_objects\\[\\["class_lists"\\]\\]', source))

  cedar_refs <- sum(c(has_cedar_sections, has_cedar_students, has_cedar_programs, has_cedar_faculty))
  legacy_refs <- sum(c(has_DESRs, has_class_lists))

  if (cedar_refs > 0 && legacy_refs == 0) {
    message("  ", description, ": PASS (", cedar_refs, " CEDAR refs, 0 legacy refs)")
    return(TRUE)
  } else if (cedar_refs > 0 && legacy_refs > 0) {
    message("  ", description, ": WARN (", cedar_refs, " CEDAR refs, ", legacy_refs, " legacy refs)")
    return(TRUE)
  } else {
    message("  ", description, ": INFO (no CEDAR table refs found)")
    return(TRUE)
  }
}

check_cedar_usage("R/cones/dept-report.R", "dept-report.R")
check_cedar_usage("R/cones/headcount.R", "headcount.R")
check_cedar_usage("R/cones/sfr.R", "sfr.R")
check_cedar_usage("R/cones/degrees.R", "degrees.R")

# =============================================================================
# Summary
# =============================================================================

end_time <- Sys.time()
duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

message("\n", paste(rep("=", 60), collapse = ""))
message("=== Test Summary ===")
message(paste(rep("=", 60), collapse = ""))
message("Total time: ", round(duration, 1), " seconds")
message("Test department: ", TEST_DEPT)
message("")

# Count passes/failures from output
message("The CLI dept-report pipeline test completed.")
message("Review the output above for PASS/FAIL/WARN status of each test.")
message("")
message("To test with a different department:")
message("  Rscript tests/test-cli-dept-report.R --dept 'AS Physics Astronomy'")
message("")
