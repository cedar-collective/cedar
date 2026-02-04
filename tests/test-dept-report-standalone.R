#!/usr/bin/env Rscript
#
# Standalone integration test for dept-report.R
#
# This smoke test validates that the department report pipeline runs without
# errors using REAL production data. It tests the full integration between
# data loading, transformation, and report generation.
#
# For unit tests with predetermined expected values, see tests/testthat/
#
# Usage:
#   Rscript tests/test-dept-report-standalone.R
#   OR
#   source("tests/test-dept-report-standalone.R")

message("=== Department Report Integration Test ===\n")

# Ensure we're in the right directory
test_dir <- getwd()
if (basename(test_dir) == "tests") {
  setwd("..")
  message("Changed directory from tests/ to project root")
}

# Load CEDAR environment (same as global.R does)
message("Loading CEDAR environment...")

# Load libraries
suppressPackageStartupMessages({
  library(tidyverse)
  library(plotly)
  library(qs)
})

# Load config
if (!file.exists("config/shiny_config.R")) {
  stop("Cannot find config/shiny_config.R - make sure you're running from CEDAR project root")
}
source("config/shiny_config.R")

# Load functions
source("R/branches/load-funcs.R")
load_funcs(cedar_base_dir)

# Configuration
TEST_DEPT <- "AS Anthropology"  # Change this to test different departments
TEST_PROG_FOCUS <- NULL  # Or specify a program code

message("Test configuration:")
message("  Department: ", TEST_DEPT)
message("  Program Focus: ", ifelse(is.null(TEST_PROG_FOCUS), "NULL (all programs)", TEST_PROG_FOCUS))
message("  Data source: ", cedar_data_dir)
message("")

# =============================================================================
# Load REAL data from cedar_data_dir (CEDAR MODEL ONLY - NO LEGACY FALLBACK)
# =============================================================================
message("Loading CEDAR data objects only...")
data_objects <- list()

# cedar_programs (required)
tryCatch({
  qs_path <- file.path(cedar_data_dir, "cedar_programs.qs")
  rds_path <- file.path(cedar_data_dir, "cedar_programs.Rds")

  if (file.exists(qs_path)) {
    data_objects$cedar_programs <- qread(qs_path)
    message("  cedar_programs: ", nrow(data_objects$cedar_programs), " rows (from cedar_programs.qs)")
  } else if (file.exists(rds_path)) {
    data_objects$cedar_programs <- readRDS(rds_path)
    message("  cedar_programs: ", nrow(data_objects$cedar_programs), " rows (from cedar_programs.Rds)")
  } else {
    stop("cedar_programs file not found in ", cedar_data_dir)
  }
}, error = function(e) {
  message("  cedar_programs: ERROR - ", e$message)
  stop(e)
})

# cedar_degrees (required)
tryCatch({
  qs_path <- file.path(cedar_data_dir, "cedar_degrees.qs")
  rds_path <- file.path(cedar_data_dir, "cedar_degrees.Rds")

  if (file.exists(qs_path)) {
    data_objects$cedar_degrees <- qread(qs_path)
    message("  cedar_degrees: ", nrow(data_objects$cedar_degrees), " rows (from cedar_degrees.qs)")
  } else if (file.exists(rds_path)) {
    data_objects$cedar_degrees <- readRDS(rds_path)
    message("  cedar_degrees: ", nrow(data_objects$cedar_degrees), " rows (from cedar_degrees.Rds)")
  } else {
    stop("cedar_degrees file not found in ", cedar_data_dir)
  }
}, error = function(e) {
  message("  cedar_degrees: ERROR - ", e$message)
  stop(e)
})

# cedar_students (required)
tryCatch({
  qs_path <- file.path(cedar_data_dir, "cedar_students.qs")
  rds_path <- file.path(cedar_data_dir, "cedar_students.Rds")

  if (file.exists(qs_path)) {
    data_objects$cedar_students <- qread(qs_path)
    message("  cedar_students: ", nrow(data_objects$cedar_students), " rows (from cedar_students.qs)")
  } else if (file.exists(rds_path)) {
    data_objects$cedar_students <- readRDS(rds_path)
    message("  cedar_students: ", nrow(data_objects$cedar_students), " rows (from cedar_students.Rds)")
  } else {
    stop("cedar_students file not found in ", cedar_data_dir)
  }
  
  # Validate CEDAR naming
  if (!"subject_course" %in% colnames(data_objects$cedar_students)) {
    stop("cedar_students is missing required CEDAR column: subject_course")
  }
}, error = function(e) {
  message("  cedar_students: ERROR - ", e$message)
  stop(e)
})

# cedar_faculty (required)
tryCatch({
  qs_path <- file.path(cedar_data_dir, "cedar_faculty.qs")
  rds_path <- file.path(cedar_data_dir, "cedar_faculty.Rds")

  if (file.exists(qs_path)) {
    data_objects$cedar_faculty <- qread(qs_path)
    message("  cedar_faculty: ", nrow(data_objects$cedar_faculty), " rows (from cedar_faculty.qs)")
  } else if (file.exists(rds_path)) {
    data_objects$cedar_faculty <- readRDS(rds_path)
    message("  cedar_faculty: ", nrow(data_objects$cedar_faculty), " rows (from cedar_faculty.Rds)")
  } else {
    stop("cedar_faculty file not found in ", cedar_data_dir)
  }

  # Validate CEDAR naming
  if (!"instructor_id" %in% colnames(data_objects$cedar_faculty)) {
    stop("cedar_faculty is missing required CEDAR column: instructor_id")
  }
}, error = function(e) {
  message("  cedar_faculty: ERROR - ", e$message)
  stop(e)
})

# cedar_sections (required)
tryCatch({
  qs_path <- file.path(cedar_data_dir, "cedar_sections.qs")
  rds_path <- file.path(cedar_data_dir, "cedar_sections.Rds")

  if (file.exists(qs_path)) {
    data_objects$cedar_sections <- qread(qs_path)
    message("  cedar_sections: ", nrow(data_objects$cedar_sections), " rows (from cedar_sections.qs)")
  } else if (file.exists(rds_path)) {
    data_objects$cedar_sections <- readRDS(rds_path)
    message("  cedar_sections: ", nrow(data_objects$cedar_sections), " rows (from cedar_sections.Rds)")
  } else {
    stop("cedar_sections file not found in ", cedar_data_dir)
  }

  # Validate CEDAR naming
  if (!"subject_course" %in% colnames(data_objects$cedar_sections)) {
    stop("cedar_sections is missing required CEDAR column: subject_course")
  }
}, error = function(e) {
  message("  cedar_sections: ERROR - ", e$message)
  stop(e)
})

message("")

# Check required data
if (length(data_objects) == 0) {
  stop("No data objects loaded! Cannot proceed with test.")
}

# =============================================================================
# Test 1: set_payload
# =============================================================================
message("\n=== Test 1: set_payload ===")
tryCatch({
  d_params <- set_payload(TEST_DEPT, TEST_PROG_FOCUS)

  message("set_payload completed successfully")
  message("  Department: ", d_params$dept_code)
  message("  Dept Name: ", d_params$dept_name)
  message("  Subject Codes: ", paste(d_params$subj_codes, collapse = ", "))
  message("  Program Codes: ", paste(d_params$prog_codes, collapse = ", "))
  message("  Program Names: ", paste(d_params$prog_names, collapse = ", "))
  message("  Term Range: ", d_params$term_start, " to ", d_params$term_end)

  # Verify structure
  required_fields <- c("dept_code", "dept_name", "subj_codes", "prog_names",
                      "prog_codes", "tables", "plots", "term_start", "term_end")
  missing <- setdiff(required_fields, names(d_params))
  if (length(missing) > 0) {
    message("  FAIL: Missing fields: ", paste(missing, collapse = ", "))
  } else {
    message("  PASS: All required fields present")
  }
}, error = function(e) {
  message("FAIL: set_payload failed: ", e$message)
  stop("Cannot continue without set_payload working")
})

# =============================================================================
# Test 2: create_dept_report_data
# =============================================================================
message("\n=== Test 2: create_dept_report_data ===")
opt <- list(
  dept = TEST_DEPT,
  prog = TEST_PROG_FOCUS,
  shiny = TRUE  # Simulate Shiny environment
)

message("Options: ", toString(opt))
message("Starting data generation...")

start_time <- Sys.time()

tryCatch({
  d_params <- create_dept_report_data(data_objects, opt)

  end_time <- Sys.time()
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

  message("\nPASS: create_dept_report_data completed in ", round(duration, 1), " seconds")

  # Analyze outputs
  message("\n=== Output Analysis ===")
  message("Tables generated (", length(d_params$tables), "):")
  if (length(d_params$tables) > 0) {
    for (table_name in names(d_params$tables)) {
      table_obj <- d_params$tables[[table_name]]
      if (!is.null(table_obj) && is.data.frame(table_obj)) {
        message("  ", table_name, ": ", nrow(table_obj), " rows x ", ncol(table_obj), " cols")
      } else if (is.null(table_obj)) {
        message("  ", table_name, ": NULL")
      } else {
        message("  ", table_name, ": ", class(table_obj)[1])
      }
    }
  } else {
    message("  (none)")
  }

  message("\nPlots generated (", length(d_params$plots), "):")
  if (length(d_params$plots) > 0) {
    for (plot_name in names(d_params$plots)) {
      plot_obj <- d_params$plots[[plot_name]]
      if (!is.null(plot_obj)) {
        plot_class <- class(plot_obj)[1]
        message("  ", plot_name, ": ", plot_class)
      } else {
        message("  ", plot_name, ": NULL")
      }
    }
  } else {
    message("  (none)")
  }

  # Check specific expected outputs
  message("\n=== Expected Outputs Check ===")

  # Headcount outputs
  headcount_tables <- c("hc_progs_under_long_majors", "hc_progs_under_long_minors",
                       "hc_progs_grad_long_majors")
  headcount_present <- sum(headcount_tables %in% names(d_params$tables))
  message("Headcount tables: ", headcount_present, "/", length(headcount_tables))

  # Degrees outputs
  degree_plots <- c("degree_summary_faceted_by_major_plot",
                   "degree_summary_filtered_program_stacked_plot")
  degree_plots_present <- sum(degree_plots %in% names(d_params$plots))
  message("Degree plots: ", degree_plots_present, "/", length(degree_plots))

  degree_tables <- c("degree_summary_filtered_program")
  degree_tables_present <- sum(degree_tables %in% names(d_params$tables))
  message("Degree tables: ", degree_tables_present, "/", length(degree_tables))

  # SFR outputs
  if ("sfr_plot" %in% names(d_params$plots)) {
    message("SFR plot: present")
  } else {
    message("SFR plot: missing")
  }

  # Summary
  total_outputs <- length(d_params$tables) + length(d_params$plots)
  message("\nTotal outputs: ", total_outputs)

  if (total_outputs == 0) {
    message("WARNING: No outputs generated. Check that data contains records for ", TEST_DEPT)
  } else {
    message("PASS: Report data generated successfully!")
  }

}, error = function(e) {
  message("\nFAIL: create_dept_report_data failed!")
  message("Error: ", e$message)
  message("\nStack trace:")
  print(e)
})

# =============================================================================
# Test 3: Verify Shiny compatibility
# =============================================================================
message("\n=== Test 3: Shiny Compatibility ===")

if (exists("d_params") && is.list(d_params)) {

  # Check plot types
  plot_types_ok <- TRUE
  for (plot_name in names(d_params$plots)) {
    plot_obj <- d_params$plots[[plot_name]]
    if (!is.null(plot_obj)) {
      valid_classes <- c("plotly", "ggplot", "htmlwidget", "gg")
      if (!any(sapply(valid_classes, function(cls) inherits(plot_obj, cls)))) {
        message("FAIL: Plot '", plot_name, "' has unexpected class: ", class(plot_obj)[1])
        plot_types_ok <- FALSE
      }
    }
  }

  if (plot_types_ok) {
    message("PASS: All plots are compatible with Shiny (plotly/ggplot/htmlwidget)")
  }

  # Check table types
  table_types_ok <- TRUE
  for (table_name in names(d_params$tables)) {
    table_obj <- d_params$tables[[table_name]]
    if (!is.null(table_obj) && !is.data.frame(table_obj)) {
      message("FAIL: Table '", table_name, "' is not a data frame: ", class(table_obj)[1])
      table_types_ok <- FALSE
    }
  }

  if (table_types_ok) {
    message("PASS: All tables are data frames")
  }

  # Check required metadata
  if (all(c("dept_code", "dept_name", "prog_names") %in% names(d_params))) {
    message("PASS: Required metadata present (dept_code, dept_name, prog_names)")
  } else {
    message("FAIL: Missing required metadata")
  }

} else {
  message("FAIL: d_params not available for testing")
}

# =============================================================================
# Test 4: CEDAR migration check
# =============================================================================
message("\n=== Test 4: CEDAR Migration Verification ===")

# Read dept-report.R source
dept_report_path <- "R/cones/dept-report.R"
if (file.exists(dept_report_path)) {
  dept_report_source <- readLines(dept_report_path)

  # Check for cedar_faculty usage
  has_cedar_faculty <- any(grepl("cedar_faculty", dept_report_source))
  if (has_cedar_faculty) {
    message("PASS: dept-report.R references cedar_faculty (CEDAR naming)")
  } else {
    message("FAIL: dept-report.R does not reference cedar_faculty")
  }

  # Check for hr_data usage - but ignore fallback code (lines with "else if")
  hr_data_lines <- grep('data_objects\\[\\["hr_data"\\]\\]', dept_report_source)
  # Filter out fallback lines (lines that have "else if" before hr_data)
  fallback_lines <- c()
  for (line_num in hr_data_lines) {
    if (line_num > 1) {
      prev_lines <- dept_report_source[(line_num-2):(line_num)]
      if (any(grepl("else if.*hr_data", prev_lines))) {
        fallback_lines <- c(fallback_lines, line_num)
      }
    }
  }

  non_fallback_hr_data <- setdiff(hr_data_lines, fallback_lines)

  if (length(non_fallback_hr_data) > 0) {
    message("FAIL: dept-report.R uses hr_data (non-fallback) on lines: ", paste(non_fallback_hr_data, collapse = ", "))
    message("  Should use cedar_faculty instead")
  } else if (length(fallback_lines) > 0) {
    message("PASS: dept-report.R uses hr_data only in fallback code (lines ",
            paste(fallback_lines, collapse = ", "), ") - OK")
  } else {
    message("PASS: dept-report.R does not use hr_data")
  }

} else {
  message("FAIL: Cannot find ", dept_report_path)
}

# =============================================================================
# Final summary
# =============================================================================
message("\n", paste(rep("=", 50), collapse = ""))
message("=== Test Complete ===")
message(paste(rep("=", 50), collapse = ""), "\n")

if (exists("d_params") && length(d_params$tables) + length(d_params$plots) > 0) {
  message("Department report data generation is working!")
  message("\nYou can now:")
  message("  1. Inspect d_params object: str(d_params, max.level = 2)")
  message("  2. View a plot: d_params$plots$degree_summary_faceted_by_major_plot")
  message("  3. View a table: View(d_params$tables$degree_summary_filtered_program)")
  message("  4. Test in Shiny app by running the full application")
} else {
  message("Tests completed but no data was generated")
  message("  Check that your test department (", TEST_DEPT, ") has data")
}

message("\nTo test with a different department, edit TEST_DEPT at top of this script")
