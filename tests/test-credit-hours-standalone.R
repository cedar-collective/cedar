#!/usr/bin/env Rscript
#
# Standalone inspection script for credit_hours_by_major()
#
# Calls credit_hours_by_major() directly against real production data and
# prints the full output for manual review. Useful for debugging the
# credit-hours branch without running the Shiny app.
#
# Usage:
#   Rscript tests/test-credit-hours-standalone.R
#   OR source("tests/test-credit-hours-standalone.R") from RStudio

message("=== Credit Hours Inspection ===\n")

if (basename(getwd()) == "tests") {
  setwd("..")
  message("Changed directory from tests/ to project root")
}

if (!file.exists("config/shiny_config.R")) {
  stop("Cannot find config/shiny_config.R — run from the cedar project root")
}

suppressPackageStartupMessages(library(tidyverse))
library(qs2)

source("config/shiny_config.R")

suppressMessages({
  source("R/trunk/load-funcs.R")
  load_funcs(cedar_base_dir)
})

TEST_DEPT <- "BIOL"   # change this to test a different department

message("Test configuration:")
message("  Department: ", TEST_DEPT)
message("  Data source: ", cedar_data_dir)
message("")

# =============================================================================
# Load data
# =============================================================================
message("Loading cedar_students...")
tryCatch({
  cedar_students <- qs2::qs_read(file.path(cedar_data_dir, "cedar_students.qs"))
  message("  cedar_students: ", nrow(cedar_students), " rows")
}, error = function(e) {
  stop("Failed to load cedar_students.qs: ", e$message)
})

# =============================================================================
# set_payload
# =============================================================================
message("\n=== set_payload ===")
tryCatch({
  d_params <- suppressMessages(set_payload(TEST_DEPT))
  message("PASS: set_payload completed")
  message("  dept:   ", d_params$dept_code, " — ", d_params$dept_name)
  message("  majors: ", paste(d_params$prog_codes, collapse = ", "))
  message("  terms:  ", d_params$term_start, " – ", d_params$term_end)
}, error = function(e) {
  stop("FAIL: set_payload failed: ", e$message)
})

dept_students <- cedar_students %>% filter(department == d_params$dept_code)
message("\n  dept rows: ", nrow(dept_students))

# =============================================================================
# credit_hours_by_major
# =============================================================================
message("\n=== credit_hours_by_major ===")
tryCatch({
  result <- suppressMessages(
    credit_hours_by_major(
      dept_students,
      d_params$dept_code,
      d_params$prog_codes,
      d_params$term_start,
      d_params$term_end
    )
  )

  message("PASS: credit_hours_by_major completed")
  message("  Tables: ", paste(names(result$tables), collapse = ", "))
  message("  Plots:  ", paste(names(result$plots),  collapse = ", "))

  message("\n=== Lower Division — outside majors (full ranked list) ===")
  print(result$tables$sch_outside_full_lower, n = Inf)

  message("\n=== Upper Division — outside majors (full ranked list) ===")
  print(result$tables$sch_outside_full_upper, n = Inf)

  message("\n=== Lower Division — growing/declining outside majors ===")
  message("Growing:")
  print(result$tables$sch_major_trends_lower$growing,   n = Inf)
  message("Declining:")
  print(result$tables$sch_major_trends_lower$declining, n = Inf)

  message("\n=== Upper Division — growing/declining outside majors ===")
  message("Growing:")
  print(result$tables$sch_major_trends_upper$growing,   n = Inf)
  message("Declining:")
  print(result$tables$sch_major_trends_upper$declining, n = Inf)

}, error = function(e) {
  message("FAIL: credit_hours_by_major failed: ", e$message)
  print(e)
})

message("\n=== Inspection complete ===")
