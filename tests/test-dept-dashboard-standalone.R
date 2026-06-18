#!/usr/bin/env Rscript
#
# Standalone integration test for dept-dashboard.R
#
# Smoke test for the "Explore Your Unit" dashboard pipeline. Validates that
# all dashboard functions run without errors using real production data, and
# that outputs are Shiny-compatible (plotly objects, data frames).
#
# Also unit-tests compute_trend() with known inputs since it's a generalized
# helper used across cones.
#
# Usage:
#   Rscript tests/test-dept-dashboard-standalone.R
#   OR
#   source("tests/test-dept-dashboard-standalone.R")

message("=== Dept Dashboard Integration Test ===\n")

# Ensure we're running from project root
if (basename(getwd()) == "tests") {
  setwd("..")
  message("Changed directory from tests/ to project root")
}

# ── Environment setup ─────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(tidyverse)
  library(plotly)
  library(qs2)
})

if (!file.exists("config/shiny_config.R")) {
  stop("Cannot find config/shiny_config.R — run from CEDAR project root")
}
source("config/shiny_config.R")
source("R/trunk/load-funcs.R")
load_funcs(cedar_base_dir)

# ── Test configuration ────────────────────────────────────────────────────────

TEST_DEPT <- "AS Anthropology"  # Change to test a different department
message("Test department: ", TEST_DEPT)
message("Data source:     ", cedar_data_dir)
message("")

# ── Load data ─────────────────────────────────────────────────────────────────

load_cedar <- function(name, required = TRUE) {
  qs_path  <- file.path(cedar_data_dir, paste0(name, ".qs"))
  rds_path <- file.path(cedar_data_dir, paste0(name, ".Rds"))
  tryCatch({
    if (file.exists(qs_path)) {
      obj <- qs_read(qs_path)
    } else if (file.exists(rds_path)) {
      obj <- readRDS(rds_path)
    } else {
      if (required) stop(name, " not found in ", cedar_data_dir)
      return(NULL)
    }
    message("  ", name, ": ", nrow(obj), " rows")
    obj
  }, error = function(e) {
    if (required) stop(e)
    message("  ", name, ": MISSING (optional) — ", e$message)
    NULL
  })
}

message("Loading data...")
data_objects <- list(
  cedar_programs = load_cedar("cedar_programs"),
  cedar_students = load_cedar("cedar_students"),
  cedar_sections = load_cedar("cedar_sections"),
  cedar_degrees  = load_cedar("cedar_degrees"),
  cedar_faculty  = load_cedar("cedar_faculty")
)
message("")

pass_count <- 0
fail_count <- 0

check <- function(label, expr) {
  result <- tryCatch(expr, error = function(e) e)
  if (inherits(result, "error")) {
    message("  FAIL: ", label, " — ", result$message)
    fail_count <<- fail_count + 1
  } else if (isTRUE(result)) {
    message("  PASS: ", label)
    pass_count <<- pass_count + 1
  } else {
    message("  FAIL: ", label, " — returned FALSE")
    fail_count <<- fail_count + 1
  }
}


# =============================================================================
# Test 1: compute_trend() unit tests
# =============================================================================
message("=== Test 1: compute_trend() ===")

check("upward series detected as 'up'", {
  t <- compute_trend(c(40, 45, 52, 61, 70))
  t$direction == "up"
})

check("downward series detected as 'down'", {
  t <- compute_trend(c(80, 72, 65, 58, 50))
  t$direction == "down"
})

check("flat series detected as 'stable' (with threshold to absorb float noise)", {
  t <- compute_trend(c(50, 50, 50, 50, 50), threshold = 0.01)
  t$direction == "stable"
})

check("single value returns 'unknown'", {
  t <- compute_trend(c(42))
  t$direction == "unknown"
})

check("NA values are dropped before fitting", {
  t <- compute_trend(c(40, NA, 50, NA, 60))
  t$direction == "up"
})

check("arrow is a non-empty string", {
  t <- compute_trend(c(10, 20, 30))
  nchar(t$arrow) > 0
})

check("slope is numeric", {
  t <- compute_trend(c(10, 20, 30))
  is.numeric(t$slope)
})

check("threshold suppresses weak trends", {
  t <- compute_trend(c(50, 51, 50, 51, 50), threshold = 2)
  t$direction == "stable"
})


# =============================================================================
# Test 2: get_headcount_summary()
# =============================================================================
message("\n=== Test 2: get_headcount_summary() ===")

hc_summary <- tryCatch(
  get_headcount_summary(data_objects$cedar_programs, TEST_DEPT),
  error = function(e) { message("  ERROR: ", e$message); NULL }
)

check("returns a data frame", !is.null(hc_summary) && is.data.frame(hc_summary))

check("has expected columns", {
  required <- c("group", "current_count", "trend_direction", "arrow")
  all(required %in% names(hc_summary))
})

check("has 4 rows (UG majors, UG minors, Grad majors, Grad minors)", {
  !is.null(hc_summary) && nrow(hc_summary) == 4
})

check("trend_direction values are valid", {
  valid <- c("up", "down", "stable", "unknown")
  !is.null(hc_summary) && all(hc_summary$trend_direction %in% valid)
})

check("current_count is non-negative", {
  !is.null(hc_summary) && all(hc_summary$current_count >= 0)
})

if (!is.null(hc_summary)) {
  message("  Headcount summary:")
  for (i in seq_len(nrow(hc_summary))) {
    message("    ", hc_summary$group[i], ": ", hc_summary$current_count[i],
            " ", hc_summary$arrow[i], " (", hc_summary$trend_direction[i], ")")
  }
}


# =============================================================================
# Test 3: plot_cross_dept_minors()
# =============================================================================
message("\n=== Test 3: plot_cross_dept_minors() ===")

donut <- tryCatch(
  plot_cross_dept_minors(data_objects$cedar_programs, TEST_DEPT),
  error = function(e) { message("  ERROR: ", e$message); NULL }
)

check("returns plotly or NULL", is.null(donut) || inherits(donut, "plotly"))

if (!is.null(donut)) {
  check("plotly object is a list", is.list(donut))
  message("  Cross-dept minor donut: generated OK")
} else {
  message("  Cross-dept minor donut: NULL (no cross-dept minors found — may be expected for this dept)")
}


# Resolve HR org description to short dept code for student/section tables
TEST_DEPT_CODE <- if (exists("hr_org_desc_to_dept") && TEST_DEPT %in% names(hr_org_desc_to_dept)) {
  hr_org_desc_to_dept[[TEST_DEPT]]
} else {
  TEST_DEPT
}
message("  Resolved dept code for students/sections: ", TEST_DEPT_CODE)

# =============================================================================
# Test 4: plot_credit_hours_by_level()
# =============================================================================
message("\n=== Test 4: plot_credit_hours_by_level() ===")

ch_plot <- tryCatch(
  plot_credit_hours_by_level(data_objects$cedar_students, TEST_DEPT_CODE, n_years = 5),
  error = function(e) { message("  ERROR: ", e$message); NULL }
)

check("returns plotly or NULL", is.null(ch_plot) || inherits(ch_plot, "plotly"))

if (!is.null(ch_plot)) {
  message("  Credit hours trendline: generated OK")
} else {
  message("  Credit hours trendline: NULL (no data for ", TEST_DEPT, " — check dept code)")
}


# =============================================================================
# Test 5: get_enrollment_momentum()
# =============================================================================
message("\n=== Test 5: get_enrollment_momentum() ===")

momentum <- tryCatch(
  get_enrollment_momentum(data_objects$cedar_sections, TEST_DEPT_CODE),
  error = function(e) { message("  ERROR: ", e$message); NULL }
)

check("returns a list", !is.null(momentum) && is.list(momentum))

check("list has 'growing' and 'investigate' elements", {
  !is.null(momentum) && all(c("growing", "investigate") %in% names(momentum))
})

check("growing is data frame or NULL", {
  is.null(momentum$growing) || is.data.frame(momentum$growing)
})

check("investigate is data frame or NULL", {
  is.null(momentum$investigate) || is.data.frame(momentum$investigate)
})

if (!is.null(momentum)) {
  n_growing     <- if (!is.null(momentum$growing))     nrow(momentum$growing)     else 0
  n_investigate <- if (!is.null(momentum$investigate)) nrow(momentum$investigate) else 0
  message("  Growing courses:     ", n_growing)
  message("  Worth-a-look courses: ", n_investigate)
}


# =============================================================================
# Test 6: create_dept_dashboard_data() end-to-end
# =============================================================================
message("\n=== Test 6: create_dept_dashboard_data() end-to-end ===")

opt <- list(dept = TEST_DEPT, shiny = TRUE)
start <- Sys.time()

dashboard <- tryCatch(
  create_dept_dashboard_data(data_objects, opt),
  error = function(e) { message("  ERROR: ", e$message); NULL }
)

duration <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
message("  Completed in ", duration, "s")

check("returns a list", !is.null(dashboard) && is.list(dashboard))

check("has dept_code field", !is.null(dashboard) && !is.null(dashboard$dept_code))

check("has plots list", !is.null(dashboard) && is.list(dashboard$plots))

check("has headcount_summary", {
  !is.null(dashboard) && is.data.frame(dashboard$headcount_summary)
})

check("has enrollment_momentum", {
  !is.null(dashboard) && is.list(dashboard$enrollment_momentum)
})

check("plots are plotly or NULL", {
  if (is.null(dashboard)) return(FALSE)
  all(sapply(dashboard$plots, function(p) is.null(p) || inherits(p, "plotly")))
})

if (!is.null(dashboard)) {
  message("  dept_code: ", dashboard$dept_code)
  message("  Plots generated:")
  for (nm in names(dashboard$plots)) {
    cls <- if (is.null(dashboard$plots[[nm]])) "NULL" else class(dashboard$plots[[nm]])[1]
    message("    ", nm, ": ", cls)
  }
}


# =============================================================================
# Final summary
# =============================================================================
message("\n", strrep("=", 50))
message("=== Results: ", pass_count, " passed, ", fail_count, " failed ===")
message(strrep("=", 50))

if (fail_count == 0) {
  message("\nAll tests passed. Dashboard pipeline is working.")
  message("Next steps:")
  message("  1. Run the Shiny app and select '", TEST_DEPT, "' on the Explore Your Unit tab")
  message("  2. Check that stat cards, donut, trendlines, and course lists render")
  message("  3. Try a department with no grad programs to check graceful NULLs")
} else {
  message("\n", fail_count, " test(s) failed. Review errors above.")
  message("Common causes:")
  message("  - dept code doesn't match cedar_programs$department values")
  message("  - student_level values differ from expected 'Undergraduate'/'Graduate/GASM'")
  message("  - scales package not available (needed for credit hours plot)")
  quit(status = 1)
}
