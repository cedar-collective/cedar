#!/usr/bin/env Rscript
#
# Standalone integration test for course-report.R
#
# This smoke test validates that the course report pipeline runs without
# errors using REAL production data. It tests the full integration between
# data loading, transformation, and report generation.
#
# For unit tests with predetermined expected values, see tests/testthat/
#
# Usage:
#   Rscript tests/test-course-report-standalone.R
#   OR
#   source("tests/test-course-report-standalone.R")

message("=== Course Report Integration Test ===\n")

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
TEST_COURSE <- "MATH 1350"  # Change this to test different courses
TEST_TERM <- NULL  # Or specify a term code like 202480

message("Test configuration:")
message("  Course: ", TEST_COURSE)
message("  Term: ", ifelse(is.null(TEST_TERM), "NULL (all terms)", TEST_TERM))
message("  Data source: ", cedar_data_dir)
message("")

# =============================================================================
# Load REAL data from cedar_data_dir
# =============================================================================
message("Loading production data objects (CEDAR-only)...")
data_objects <- list()

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

  # Confirm CEDAR naming
  if (!"subject_course" %in% colnames(data_objects$cedar_students)) {
    stop("cedar_students is missing required column subject_course (CEDAR naming)")
  }
}, error = function(e) {
  message("  cedar_students: ERROR - ", e$message)
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

  if (!"subject_course" %in% colnames(data_objects$cedar_sections)) {
    stop("cedar_sections is missing required column subject_course (CEDAR naming)")
  }
}, error = function(e) {
  message("  cedar_sections: ERROR - ", e$message)
  stop(e)
})

# forecasts
tryCatch({
  qs_path <- file.path(cedar_data_dir, "forecasts.qs")
  rds_path <- file.path(cedar_data_dir, "forecasts.Rds")

  if (file.exists(qs_path)) {
    data_objects$forecasts <- qread(qs_path)
    message("  forecasts: ", nrow(data_objects$forecasts), " rows (from forecasts.qs)")
  } else if (file.exists(rds_path)) {
    data_objects$forecasts <- readRDS(rds_path)
    message("  forecasts: ", nrow(data_objects$forecasts), " rows (from forecasts.Rds)")
  } else {
    message("  forecasts: NOT FOUND (will create empty)")
    data_objects$forecasts <- data.frame()
  }
}, error = function(e) {
  message("  forecasts: ERROR - ", e$message)
  data_objects$forecasts <- data.frame()
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

  if (!"instructor_id" %in% colnames(data_objects$cedar_faculty)) {
    stop("cedar_faculty is missing required column instructor_id (CEDAR naming)")
  }
}, error = function(e) {
  message("  cedar_faculty: ERROR - ", e$message)
  stop(e)
})

message("")

# Check required data
if (length(data_objects) == 0) {
  stop("No data objects loaded! Cannot proceed with test.")
}

# =============================================================================
# Test 1: Verify course exists in data
# =============================================================================
message("\n=== Test 1: Verify Course Exists ===")

if (!is.null(data_objects$cedar_students)) {
  course_col <- "subject_course"
  course_records <- sum(data_objects$cedar_students[[course_col]] == TEST_COURSE, na.rm = TRUE)
  message("  Found ", course_records, " student records for ", TEST_COURSE, " (using ", course_col, " column)")

  if (course_records == 0) {
    message("  WARNING: No records found for test course. Available courses (sample):")
    sample_courses <- unique(data_objects$cedar_students[[course_col]])[1:10]
    message("    ", paste(sample_courses, collapse = ", "))
    stop("Cannot test course report without course data")
  } else {
    message("  PASS: Course data found")
  }
} else {
  stop("No cedar_students data available")
}

# =============================================================================
# Test 2: create_course_report_data
# =============================================================================
message("\n=== Test 2: create_course_report_data ===")

opt <- list(
  course = TEST_COURSE,
  term = TEST_TERM,
  skip_forecast = TRUE,  # Skip forecasting for faster test
  skip_cache = TRUE,     # Skip cache to test full pipeline
  shiny = TRUE           # Simulate Shiny environment
)

message("Options:")
message("  course: ", opt$course)
message("  term: ", ifelse(is.null(opt$term), "NULL", opt$term))
message("  skip_forecast: ", opt$skip_forecast)
message("  skip_cache: ", opt$skip_cache)
message("")
message("Starting data generation...")

start_time <- Sys.time()

tryCatch({
  course_data <- create_course_report_data(data_objects, opt)

  end_time <- Sys.time()
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

  message("\nPASS: create_course_report_data completed in ", round(duration, 1), " seconds")

  # Analyze outputs
  message("\n=== Output Analysis ===")

  # Check top-level structure
  message("Top-level elements: ", paste(names(course_data), collapse = ", "))

  # Tables (from course_data$tables)
  if (!is.null(course_data$tables)) {
    message("\nTables generated (", length(course_data$tables), "):")
    for (table_name in names(course_data$tables)) {
      table_obj <- course_data$tables[[table_name]]
      if (!is.null(table_obj) && is.data.frame(table_obj)) {
        message("  ", table_name, ": ", nrow(table_obj), " rows x ", ncol(table_obj), " cols")
      } else if (is.null(table_obj)) {
        message("  ", table_name, ": NULL")
      } else {
        message("  ", table_name, ": ", class(table_obj)[1])
      }
    }
  } else {
    message("\nTables: (none)")
  }

  # Plots
  if (!is.null(course_data$plots)) {
    message("\nPlots generated (", length(course_data$plots), "):")
    for (plot_name in names(course_data$plots)) {
      plot_obj <- course_data$plots[[plot_name]]
      if (!is.null(plot_obj)) {
        plot_class <- class(plot_obj)[1]
        message("  ", plot_name, ": ", plot_class)
      } else {
        message("  ", plot_name, ": NULL")
      }
    }
  } else {
    message("\nPlots: (none)")
  }

  # Check specific expected outputs
  message("\n=== Expected Outputs Check ===")

  # Enrollment data
  if (!is.null(course_data$tables$cl_enrls)) {
    message("PASS: cl_enrls (enrollment data) present - ", nrow(course_data$tables$cl_enrls), " rows")
  } else {
    message("WARN: cl_enrls (enrollment data) missing")
  }

  # Lookout data (where_from, where_to, where_at)
  lookout_tables <- c("where_from", "where_to", "where_at")
  lookout_present <- sum(lookout_tables %in% names(course_data$tables))
  message("Lookout tables: ", lookout_present, "/", length(lookout_tables))

  # Rollcall data
  rollcall_tables <- c("rollcall_by_class", "rollcall_by_major")
  rollcall_present <- sum(rollcall_tables %in% names(course_data$tables))
  message("Rollcall tables: ", rollcall_present, "/", length(rollcall_tables))

  # Grade data
  if (!is.null(course_data$tables$grade_data)) {
    message("PASS: grade_data present")
    if (is.list(course_data$tables$grade_data)) {
      message("  Grade data elements: ", paste(names(course_data$tables$grade_data), collapse = ", "))
    }
  } else {
    message("WARN: grade_data missing")
  }

  # Plots check
  expected_plots <- c("enrollment_plot", "rollcall_by_class_plot", "rollcall_by_major_plot",
                      "dfw_summary_plot", "dfw_by_term_plot")
  plots_present <- sum(expected_plots %in% names(course_data$plots))
  message("Expected plots: ", plots_present, "/", length(expected_plots))

  # Summary
  total_tables <- length(course_data$tables)
  total_plots <- length(course_data$plots)
  message("\nTotal outputs: ", total_tables, " tables, ", total_plots, " plots")

  if (total_tables + total_plots == 0) {
    message("WARNING: No outputs generated. Check that data contains records for ", TEST_COURSE)
  } else {
    message("PASS: Course report data generated successfully!")
  }

}, error = function(e) {
  message("\nFAIL: create_course_report_data failed!")
  message("Error: ", e$message)
  message("\nStack trace:")
  print(e)
})

# =============================================================================
# Test 3: Verify Shiny compatibility
# =============================================================================
message("\n=== Test 3: Shiny Compatibility ===")

if (exists("course_data") && is.list(course_data)) {

  # Check plot types
  plot_types_ok <- TRUE
  if (!is.null(course_data$plots)) {
    for (plot_name in names(course_data$plots)) {
      plot_obj <- course_data$plots[[plot_name]]
      if (!is.null(plot_obj)) {
        valid_classes <- c("plotly", "ggplot", "htmlwidget", "gg", "list")
        if (!any(sapply(valid_classes, function(cls) inherits(plot_obj, cls)))) {
          message("WARN: Plot '", plot_name, "' has unexpected class: ", class(plot_obj)[1])
          plot_types_ok <- FALSE
        }
      }
    }
  }

  if (plot_types_ok) {
    message("PASS: All plots are compatible with Shiny")
  }

  # Check table types
  table_types_ok <- TRUE
  if (!is.null(course_data$tables)) {
    for (table_name in names(course_data$tables)) {
      table_obj <- course_data$tables[[table_name]]
      if (!is.null(table_obj) && !is.data.frame(table_obj) && !is.list(table_obj)) {
        message("WARN: Table '", table_name, "' is not a data frame or list: ", class(table_obj)[1])
        table_types_ok <- FALSE
      }
    }
  }

  if (table_types_ok) {
    message("PASS: All tables are valid types")
  }

  # Check required metadata
  if (all(c("course_code", "course_name") %in% names(course_data))) {
    message("PASS: Required metadata present (course_code, course_name)")
  } else {
    message("WARN: Missing required metadata")
  }

} else {
  message("FAIL: course_data not available for testing")
}

# =============================================================================
# Test 4: CEDAR column naming verification
# =============================================================================
message("\n=== Test 4: CEDAR Column Naming Verification ===")

# Read course-report.R source
course_report_path <- "R/cones/course-report.R"
if (file.exists(course_report_path)) {
  course_report_source <- readLines(course_report_path)

  # Check for old column names that should have been migrated
  old_patterns <- list(
    "SUBJ_CRSE" = "subject_course",
    "Academic Period Code" = "term",
    "Course Campus Code" = "campus",
    "Course College Code" = "college",
    "Student Classification" = "student_classification",
    "Short Course Title" = "course_title",
    "CRSE_TITLE" = "course_title",
    "CAMP" = "campus",
    "COLLEGE" = "college"
  )

  issues_found <- FALSE
  for (old_name in names(old_patterns)) {
    # Escape special characters for regex
    escaped_name <- gsub("([\\[\\]])", "\\\\\\1", old_name)
    matches <- grep(escaped_name, course_report_source, ignore.case = FALSE)

    if (length(matches) > 0) {
      message("WARN: Found old column name '", old_name, "' on lines: ", paste(matches, collapse = ", "))
      message("  Should be: ", old_patterns[[old_name]])
      issues_found <- TRUE
    }
  }

  if (!issues_found) {
    message("PASS: No old column naming patterns found in course-report.R")
  }

} else {
  message("WARN: Cannot find ", course_report_path)
}

# =============================================================================
# Final summary
# =============================================================================
message("\n", paste(rep("=", 50), collapse = ""))
message("=== Test Complete ===")
message(paste(rep("=", 50), collapse = ""), "\n")

if (exists("course_data") && (length(course_data$tables) + length(course_data$plots)) > 0) {
  message("Course report data generation is working!")
  message("\nYou can now:")
  message("  1. Inspect course_data object: str(course_data, max.level = 2)")
  message("  2. View a plot: course_data$plots$enrollment_plot")
  message("  3. View a table: View(course_data$tables$rollcall_by_class)")
  message("  4. Test in Shiny app by running the full application")
} else {
  message("Tests completed but no data was generated")
  message("  Check that your test course (", TEST_COURSE, ") has data")
}

message("\nTo test with a different course, edit TEST_COURSE at top of this script")
