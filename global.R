message("[global.R] Welcome to global.R!")
message("[global.R] CEDAR-ONLY DATA MODEL - All data must be in CEDAR format")

# Note: renv is already activated by .Rprofile -> renv/activate.R when R starts
# No need to call renv::activate() again here

# Function to detect if running in Docker
is_docker <- function() {
  file.exists("/.dockerenv") ||
    (file.exists("/proc/1/cgroup") && any(grepl("docker|containerd", readLines("/proc/1/cgroup"))))
}

# Log environment
if (is_docker()) {
  message("[global.R] Running inside a Docker container.")
  Sys.setenv("docker" = TRUE)
} else {
  message("[global.R] Running locally or in an unknown environment.")
  Sys.setenv("docker" = FALSE)
}

# Set Shiny environment variable to be TRUE
message("[global.R] Setting shiny environment variable to be TRUE...")
Sys.setenv("shiny" = TRUE)

message("[global.R] Loading libraries...")
library(jsonlite)
library(shiny)
library(plotly)
library(DT)
library(bslib)
library(tidyverse)
library(htmlwidgets)
library(htmltools)
library(yaml)
library(qs)

message("[global.R] Loading shiny_config...")
source("config/shiny_config.R")

message("[global.R] Loading functions...")
source("R/branches/load-funcs.R")

message("[global.R] Calling load_funcs...")
load_funcs(cedar_base_dir)


# Copy all .html files from data/ to www/ at startup
# This allows them to be served by the Shiny server
data_dir <- file.path(getwd(), "data")
www_dir <- file.path(getwd(), "www")

if (dir.exists(data_dir)) {
  html_files <- list.files(data_dir, pattern = "\\.html$", full.names = TRUE)
  if (length(html_files) > 0) {
    if (!dir.exists(www_dir)) {
     dir.create(www_dir, recursive = TRUE)
    }
    file.copy(html_files, www_dir, overwrite = TRUE)
    message("[global.R] Copied HTML reports from data/ to www/: ", paste(basename(html_files), collapse = ", "))
  }
}

# if running in a docker container, look for data in the usual data dir
if (is_docker()) {
  docker_data_dir <- "/srv/shiny-server/cedar/data/"
  message("[global.R] Loading data files for Docker environment. Data dir: ", docker_data_dir)

  # Helper function to time data loading
  timed_read_data <- function(path, label) {
    message(sprintf("loading %s...", label))
    t <- system.time({ obj <- load_cedar_data(path) })
    message(sprintf("[global.R] Loaded %s in %.2f seconds.", label, t["elapsed"]))
    obj
  }

#=============================================================================
# CEDAR DATA LOADING - CEDAR-ONLY APPROACH
#=============================================================================
# This section enforces CEDAR data model naming conventions.
# All data must be in CEDAR format with lowercase column names and underscores.
#
# CEDAR Data Files:
#   - cedar_sections.qs    - Course sections
#   - cedar_students.qs    - Student enrollments
#   - cedar_programs.qs    - Program enrollments
#   - cedar_degrees.qs     - Degrees awarded
#   - cedar_faculty.qs     - Faculty data
#   - cedar_lookups.qs     - Auto-generated normalization tables (program_lookup, dept_lookup, subject_lookup)
#   - forecasts.qs         - Enrollment forecasts (optional)
#
# data_objects Structure (what cones expect):
#   data_objects[["cedar_sections"]]  - Course sections
#   data_objects[["cedar_students"]]  - Student enrollments
#   data_objects[["cedar_programs"]]  - Program enrollments
#   data_objects[["cedar_degrees"]]   - Degrees awarded
#   data_objects[["cedar_faculty"]]   - Faculty data
#   data_objects[["cedar_lookups"]]   - Normalization tables (list with program_lookup, dept_lookup, subject_lookup)
#   data_objects[["forecasts"]]       - Enrollment forecasts
#
# Note: Some cones may still reference legacy keys (DESRs, class_lists,
#       academic_studies) for backwards compatibility during transition.
#       These will be aliases that point to the CEDAR data.
#=============================================================================

# CEDAR file list - these are the actual file names on disk
cedar_files <- list(
  cedar_sections = "cedar_sections",
  cedar_students = "cedar_students",
  cedar_programs = "cedar_programs",
  cedar_degrees = "cedar_degrees",
  cedar_faculty = "cedar_faculty",
  cedar_lookups = "cedar_lookups",  # Auto-generated normalization tables
  forecasts = "forecasts"
)

# Function to get the correct file path (regular or _small)
get_cedar_data_path <- function(base_name, data_dir, use_small = FALSE) {
  ext <- get_data_extension()
  message(sprintf("[global.R] get_data_extension() returned: %s", ext))

  if (use_small) {
    # Try QS format for small file
    small_path_qs <- file.path(data_dir, paste0(base_name, "_small.qs"))
    if (file.exists(small_path_qs)) {
      message(sprintf("[global.R] Using small data file: %s", small_path_qs))
      return(small_path_qs)
    }

    # Try RDS format for small file
    small_path_rds <- file.path(data_dir, paste0(base_name, "_small.Rds"))
    if (file.exists(small_path_rds)) {
      message(sprintf("[global.R] Using small data file: %s", small_path_rds))
      return(small_path_rds)
    }

    message(sprintf("[global.R] No small data file found for %s, falling back to full dataset", base_name))
  }

  # Return path with preferred extension (load_cedar_data will handle fallback)
  full_path <- file.path(data_dir, paste0(base_name, ext))
  message(sprintf("[global.R] Using full data file: %s", full_path))
  return(full_path)
}

# Validate CEDAR data structure
validate_cedar_data <- function(data, data_name, required_cols) {
  if (is.null(data)) {
    warning(sprintf("[global.R] %s is NULL - skipping validation", data_name))
    return(FALSE)
  }

  if (nrow(data) == 0) {
    warning(sprintf("[global.R] %s has 0 rows - skipping validation", data_name))
    return(FALSE)
  }

  missing_cols <- setdiff(required_cols, colnames(data))

  if (length(missing_cols) > 0) {
    stop(sprintf("[global.R] %s is missing required CEDAR columns: %s\n",
                 data_name,
                 paste(missing_cols, collapse = ", ")),
         sprintf("  Expected CEDAR format with lowercase column names.\n"),
         sprintf("  Found columns: %s\n", paste(colnames(data), collapse = ", ")),
         sprintf("  Ensure data files are in CEDAR format."))
  }

  message(sprintf("[global.R] ✓ %s validated: %d rows, %d columns",
                  data_name, nrow(data), ncol(data)))
  return(TRUE)
}

# Load all CEDAR data files into a named list
data_objects <- list()

# Iterate over each CEDAR file and load it
for (key in names(cedar_files)) {
  cedar_file_name <- cedar_files[[key]]
  use_small <- exists("cedar_use_small_data") && isTRUE(cedar_use_small_data)

  message(sprintf("[global.R] Loading %s from file: %s (use_small: %s)...",
                  key, cedar_file_name, use_small))

  data_path <- get_cedar_data_path(cedar_file_name, data_dir, use_small)
  message(sprintf("[global.R] Data path: %s", data_path))

  # Let load_cedar_data handle file existence and format fallback (QS -> RDS)
  data_objects[[key]] <- timed_read_data(data_path, basename(data_path))
}

message("[global.R] Data loading complete. Validating CEDAR data structure...")

# Validate critical CEDAR datasets
# These validations ensure data is in CEDAR format before the app starts
validation_specs <- list(
  cedar_sections = c("section_id", "term", "department", "instructor_id", "subject_course", "part_term"),
  cedar_students = c("student_id", "term", "department", "final_grade", "credits", "subject_code", "level", "instructor_id", "part_term"),
  cedar_programs = c("term", "student_level", "program_type", "program_name", "department", "student_college", "student_campus"),
  cedar_degrees = c("term", "degree", "program_code"),
  cedar_faculty = c("term", "instructor_id", "department", "job_category")
)

validation_failed <- FALSE
for (key in names(validation_specs)) {
  if (!validate_cedar_data(data_objects[[key]], key, validation_specs[[key]])) {
    if (key != "forecasts") {  # forecasts is optional
      validation_failed <- TRUE
    }
  }
}

if (validation_failed) {
  stop("[global.R] CEDAR data validation failed. Cannot start application.\n",
       "  Please ensure all data files are in CEDAR format.")
}

message("[global.R] ✅ All CEDAR data validated successfully!")

message("[global.R] Data objects ready:")
message("  - cedar_sections: ", nrow(data_objects[["cedar_sections"]]), " rows")
message("  - cedar_students: ", nrow(data_objects[["cedar_students"]]), " rows")
message("  - cedar_programs: ", nrow(data_objects[["cedar_programs"]]), " rows")
message("  - cedar_degrees: ", nrow(data_objects[["cedar_degrees"]]), " rows")
message("  - cedar_faculty: ", nrow(data_objects[["cedar_faculty"]]), " rows")
if (!is.null(data_objects[["cedar_lookups"]])) {
  lookups <- data_objects[["cedar_lookups"]]
  message("  - cedar_lookups: ", length(lookups), " tables (", paste(names(lookups), collapse = ", "), ")")
}
if (!is.null(data_objects[["forecasts"]])) {
  message("  - forecasts: ", nrow(data_objects[["forecasts"]]), " rows")
}

} # end data loading for docker

# ── Ensure crosslist_external column exists ──────────────────────────────────
# Added in transform-to-cedar.R after 2026-03; compute on-the-fly from older .qs files.
if (!is.null(data_objects[["cedar_sections"]]) &&
    !"crosslist_external" %in% colnames(data_objects[["cedar_sections"]])) {
  message("[global.R] crosslist_external not found — computing from crosslist_group/department...")
  xlist_dept_scope <- data_objects[["cedar_sections"]] %>%
    filter(!is.na(crosslist_group)) %>%
    group_by(term, crosslist_group) %>%
    summarize(crosslist_external = n_distinct(department) > 1, .groups = "drop")
  data_objects[["cedar_sections"]] <- data_objects[["cedar_sections"]] %>%
    left_join(xlist_dept_scope, by = c("term", "crosslist_group"))
  message("[global.R] ✅ crosslist_external computed for ", nrow(xlist_dept_scope), " crosslist groups")
}

# ── Pre-compute data summary for Data & Usage page ─────────────────────────
# This avoids expensive reactive computations and makes the tab load instantly
message("[global.R] Pre-computing data summary...")

cedar_data_summary <- list()

# Sections data
if (!is.null(data_objects[["cedar_sections"]]) && nrow(data_objects[["cedar_sections"]]) > 0) {
  sections <- data_objects[["cedar_sections"]]
  cedar_data_summary$sections_last_updated <- max(sections$as_of_date, na.rm = TRUE)
  cedar_data_summary$sections_terms <- paste(sort(unique(sections$term)), collapse = ", ")
  cedar_data_summary$sections_count <- nrow(sections)
  cedar_data_summary$sections_active_count <- sum(sections$status == "A", na.rm = TRUE)
  cedar_data_summary$sections_cancelled_count <- sum(sections$status == "C", na.rm = TRUE)
} else {
  cedar_data_summary$sections_last_updated <- NA
  cedar_data_summary$sections_terms <- "No data"
  cedar_data_summary$sections_count <- 0
  cedar_data_summary$sections_active_count <- 0
  cedar_data_summary$sections_cancelled_count <- 0
}

# Students data
if (!is.null(data_objects[["cedar_students"]]) && nrow(data_objects[["cedar_students"]]) > 0) {
  students <- data_objects[["cedar_students"]]
  cedar_data_summary$students_last_updated <- max(students$as_of_date, na.rm = TRUE)
  cedar_data_summary$students_count <- nrow(students)
  cedar_data_summary$students_unique_count <- length(unique(students$student_id))
} else {
  cedar_data_summary$students_last_updated <- NA
  cedar_data_summary$students_count <- 0
  cedar_data_summary$students_unique_count <- 0
}

# Programs data
if (!is.null(data_objects[["cedar_programs"]]) && nrow(data_objects[["cedar_programs"]]) > 0) {
  programs <- data_objects[["cedar_programs"]]
  cedar_data_summary$programs_last_updated <- max(programs$as_of_date, na.rm = TRUE)
  cedar_data_summary$programs_count <- nrow(programs)
  cedar_data_summary$programs_unique_students <- length(unique(programs$student_id))
} else {
  cedar_data_summary$programs_last_updated <- NA
  cedar_data_summary$programs_count <- 0
  cedar_data_summary$programs_unique_students <- 0
}

# Degrees data
if (!is.null(data_objects[["cedar_degrees"]]) && nrow(data_objects[["cedar_degrees"]]) > 0) {
  degrees <- data_objects[["cedar_degrees"]]
  cedar_data_summary$degrees_last_updated <- max(degrees$as_of_date, na.rm = TRUE)
  cedar_data_summary$degrees_count <- nrow(degrees)
  cedar_data_summary$degrees_terms <- paste(sort(unique(degrees$term)), collapse = ", ")
} else {
  cedar_data_summary$degrees_last_updated <- NA
  cedar_data_summary$degrees_count <- 0
  cedar_data_summary$degrees_terms <- "No data"
}

# Faculty data
if (!is.null(data_objects[["cedar_faculty"]]) && nrow(data_objects[["cedar_faculty"]]) > 0) {
  faculty <- data_objects[["cedar_faculty"]]
  cedar_data_summary$faculty_last_updated <- max(faculty$as_of_date, na.rm = TRUE)
  cedar_data_summary$faculty_count <- nrow(faculty)
  cedar_data_summary$faculty_unique_count <- length(unique(faculty$instructor_id))
} else {
  cedar_data_summary$faculty_last_updated <- NA
  cedar_data_summary$faculty_count <- 0
  cedar_data_summary$faculty_unique_count <- 0
}

# Forecasts data
if (!is.null(data_objects[["forecasts"]]) && nrow(data_objects[["forecasts"]]) > 0) {
  forecasts <- data_objects[["forecasts"]]
  cedar_data_summary$forecasts_count <- nrow(forecasts)
  cedar_data_summary$forecasts_available <- TRUE
} else {
  cedar_data_summary$forecasts_count <- 0
  cedar_data_summary$forecasts_available <- FALSE
}

# Timestamp when computed
cedar_data_summary$computed_at <- Sys.time()

message("[global.R] ✓ Data summary computed successfully")

# Initialize logging system
message("[global.R] Initializing logging system...")
init_logging()

message("[global.R] Loading ui.R and server.R...")
source("ui.R")
source("server.R")
