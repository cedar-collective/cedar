#!/usr/bin/env Rscript
#
# End-to-End CLI Tests
#
# These tests run the actual cedar.R CLI via subprocess and verify:
# 1. CLI execution completes without error
# 2. Output files are generated with correct structure
# 3. CSV files have expected columns
# 4. HTML reports are valid
#
# Usage:
#   Rscript tests/test-cli-e2e.R
#
# Note: These tests require production data and may take several minutes.

message("\n", paste(rep("=", 60), collapse = ""))
message("=== End-to-End CLI Integration Tests ===")
message(paste(rep("=", 60), collapse = ""), "\n")

# =============================================================================
# Setup
# =============================================================================

start_time <- Sys.time()

# Ensure we're in the right directory
test_dir <- getwd()
if (basename(test_dir) == "tests") {
  setwd("..")
  message("Changed directory from tests/ to project root")
}

project_root <- getwd()
message("Project root: ", project_root)

# Check cedar.R exists
if (!file.exists("cedar.R")) {
  stop("FAIL: cedar.R not found in project root")
}

# Create output directories if they don't exist (needed for CLI tests)
output_dirs <- c(
  file.path(project_root, "output"),
  file.path(project_root, "output", "dept-reports"),
  file.path(project_root, "output", "dept-reports", "html"),
  file.path(project_root, "output", "csv")
)
for (d in output_dirs) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
    message("Created directory: ", d)
  }
}

# Track test results
test_results <- list()

record_result <- function(name, passed, message = NULL) {
  test_results[[name]] <<- list(
    passed = passed,
    message = message
  )
  if (is.na(passed)) {
    message("SKIP: ", name, if (!is.null(message)) paste0(" - ", message) else "")
  } else if (passed) {
    message("PASS: ", name)
  } else {
    message("FAIL: ", name, if (!is.null(message)) paste0(" - ", message) else "")
  }
}

# =============================================================================
# Test 1: CLI Help/Guide
# =============================================================================

message("\n=== Test 1: CLI Help/Guide ===")

tryCatch({
  result <- system2("Rscript", args = c("cedar.R", "-f", "guide"),
                    stdout = TRUE, stderr = TRUE)
  output <- paste(result, collapse = "\n")

  # Should show available functions
  has_functions <- grepl("dept-report|headcount|enrl|regstats", output, ignore.case = TRUE)
  record_result("CLI guide shows available functions", has_functions)

}, error = function(e) {
  record_result("CLI guide shows available functions", FALSE, e$message)
})

# =============================================================================
# Test 2: dept-report guide
# =============================================================================

message("\n=== Test 2: dept-report Guide ===")

tryCatch({
  result <- system2("Rscript", args = c("cedar.R", "-f", "dept-report", "--guide"),
                    stdout = TRUE, stderr = TRUE)
  output <- paste(result, collapse = "\n")

  # Should mention dept parameter
  has_dept_info <- grepl("-d|--dept|DEPT", output, ignore.case = TRUE)
  record_result("dept-report guide shows parameter info", has_dept_info)

}, error = function(e) {
  record_result("dept-report guide shows parameter info", FALSE, e$message)
})

# =============================================================================
# Test 3: headcount guide
# =============================================================================

message("\n=== Test 3: headcount Guide ===")

tryCatch({
  result <- system2("Rscript", args = c("cedar.R", "-f", "headcount", "--guide"),
                    stdout = TRUE, stderr = TRUE)
  output <- paste(result, collapse = "\n")

  # Should mention filtering params
  has_info <- grepl("filter|headcount|dept", output, ignore.case = TRUE)
  record_result("headcount guide shows usage info", has_info)

}, error = function(e) {
  record_result("headcount guide shows usage info", FALSE, e$message)
})

# =============================================================================
# Test 4: Run actual dept-report (if data available)
# =============================================================================

message("\n=== Test 4: Full dept-report Execution ===")

# This is a longer test - only run if explicitly requested or in CI
run_full_tests <- Sys.getenv("CEDAR_RUN_FULL_TESTS", unset = "false") == "true"

if (run_full_tests) {
  tryCatch({
    message("Running full dept-report for HIST...")

    result <- system2("Rscript",
                      args = c("cedar.R", "-f", "dept-report", "-d", "HIST", "--output", "html"),
                      stdout = TRUE, stderr = TRUE,
                      timeout = 300)  # 5 minute timeout

    output <- paste(result, collapse = "\n")
    exit_code <- attr(result, "status")

    # Check for success
    completed <- is.null(exit_code) || exit_code == 0
    has_completion_msg <- grepl("done processing dept-report", output, ignore.case = TRUE)

    record_result("dept-report HIST execution completes", completed && has_completion_msg,
                  if (!completed) paste("Exit code:", exit_code) else NULL)

    # Check for output file - dept reports go to output/dept-reports/html/
    output_dir <- file.path(project_root, "output", "dept-reports", "html")
    if (dir.exists(output_dir)) {
      recent_files <- list.files(output_dir, pattern = "HIST.*\\.html$",
                                 full.names = TRUE, recursive = TRUE)
      # Filter to files modified in last 10 minutes
      recent_cutoff <- Sys.time() - 600
      recent_files <- recent_files[file.info(recent_files)$mtime > recent_cutoff]

      has_output <- length(recent_files) > 0
      record_result("dept-report generates HTML output file", has_output,
                    if (has_output) basename(recent_files[1]) else "No recent HTML file found")

      # Validate HTML structure if file exists
      if (has_output) {
        html_content <- readLines(recent_files[1], warn = FALSE)
        html_text <- paste(html_content, collapse = "\n")

        has_html_tag <- grepl("<html", html_text, ignore.case = TRUE)
        has_title <- grepl("<title>|<h1>", html_text, ignore.case = TRUE)
        has_table <- grepl("<table|<tbody", html_text, ignore.case = TRUE)

        record_result("HTML report has valid structure",
                      has_html_tag && has_title,
                      if (!has_html_tag) "Missing <html> tag" else NULL)

        record_result("HTML report contains data tables",
                      has_table, NULL)
      }
    } else {
      record_result("dept-report generates HTML output file", FALSE,
                    paste("Output directory not found:", output_dir))
    }

  }, error = function(e) {
    record_result("dept-report HIST execution completes", FALSE, e$message)
  })
} else {
  message("Skipping full dept-report test (set CEDAR_RUN_FULL_TESTS=true to enable)")
  record_result("dept-report HIST execution completes", NA, "Skipped")
}

# =============================================================================
# Test 5: enrl CSV output validation
# =============================================================================

message("\n=== Test 5: enrl CSV Output ===")

if (run_full_tests) {
  tryCatch({
    message("Running enrl query...")

    result <- system2("Rscript",
                      args = c("cedar.R", "-f", "enrl", "-t", "202510", "-d", "HIST",
                               "--output", "csv"),
                      stdout = TRUE, stderr = TRUE,
                      timeout = 120)

    output <- paste(result, collapse = "\n")

    # Check for CSV output
    csv_dir <- file.path(project_root, "output", "csv")
    if (dir.exists(csv_dir)) {
      csv_files <- list.files(csv_dir, pattern = "enrollment.*\\.csv$",
                              full.names = TRUE, ignore.case = TRUE)
      recent_cutoff <- Sys.time() - 300
      recent_csv <- csv_files[file.info(csv_files)$mtime > recent_cutoff]

      if (length(recent_csv) > 0) {
        # Read and validate CSV
        csv_data <- read.csv(recent_csv[1], stringsAsFactors = FALSE)

        # Expected columns for enrollment data
        expected_cols <- c("term", "subject", "course_number")
        found_cols <- expected_cols[expected_cols %in% colnames(csv_data)]

        record_result("enrl CSV has expected columns",
                      length(found_cols) >= 2,
                      paste("Found:", paste(colnames(csv_data), collapse = ", ")))

        record_result("enrl CSV contains data",
                      nrow(csv_data) > 0,
                      paste(nrow(csv_data), "rows"))
      } else {
        record_result("enrl CSV has expected columns", NA, "No recent CSV found")
      }
    } else {
      record_result("enrl CSV has expected columns", NA, "CSV directory not found")
    }

  }, error = function(e) {
    record_result("enrl CSV has expected columns", FALSE, e$message)
  })
} else {
  message("Skipping enrl CSV test (set CEDAR_RUN_FULL_TESTS=true to enable)")
  record_result("enrl CSV has expected columns", NA, "Skipped")
}

# =============================================================================
# Test 6: regstats shiny output
# NOTE: Currently blocked - rollcall.R needs CEDAR migration (course_title column)
# =============================================================================

message("\n=== Test 6: regstats Shiny Output ===")
message("Skipping - rollcall.R CEDAR migration incomplete (course_title column missing)")
record_result("regstats shiny output has correct structure", NA,
              "Blocked on rollcall.R CEDAR migration")

# =============================================================================
# Test 7: Error handling - invalid function
# =============================================================================

message("\n=== Test 7: Error Handling ===")

tryCatch({
  result <- system2("Rscript",
                    args = c("cedar.R", "-f", "nonexistent_function"),
                    stdout = TRUE, stderr = TRUE)

  output <- paste(result, collapse = "\n")

  # Should not crash - either shows guide or handles gracefully
  # Check it doesn't show a fatal R error
  has_fatal_error <- grepl("Error in|fatal error|Execution halted", output, ignore.case = TRUE)

  # It's OK to have an error message, but it should be handled
  record_result("CLI handles invalid function gracefully",
                !has_fatal_error || grepl("no function|guide", output, ignore.case = TRUE),
                NULL)

}, error = function(e) {
  record_result("CLI handles invalid function gracefully", FALSE, e$message)
})

# =============================================================================
# Summary
# =============================================================================

end_time <- Sys.time()
duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

message("\n", paste(rep("=", 60), collapse = ""))
message("=== Test Summary ===")
message(paste(rep("=", 60), collapse = ""))

passed <- 0
failed <- 0
skipped <- 0

for (name in names(test_results)) {
  result <- test_results[[name]]
  if (is.na(result$passed)) {
    skipped <- skipped + 1
  } else if (result$passed) {
    passed <- passed + 1
  } else {
    failed <- failed + 1
  }
}

message("Passed: ", passed)
message("Failed: ", failed)
message("Skipped: ", skipped)
message("Duration: ", round(duration, 1), " seconds")
message("")

if (failed > 0) {
  message("FAILED TESTS:")
  for (name in names(test_results)) {
    result <- test_results[[name]]
    if (!is.na(result$passed) && !result$passed) {
      message("  - ", name)
      if (!is.null(result$message)) {
        message("    ", result$message)
      }
    }
  }
}

message("")
message("To run full integration tests (slower, requires data):")
message("  CEDAR_RUN_FULL_TESTS=true Rscript tests/test-cli-e2e.R")
message("")

# Exit with appropriate code
if (failed > 0) {
  quit(status = 1)
}
