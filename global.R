message("[global.R] Welcome to global.R!")
message("[global.R] CEDAR-ONLY DATA MODEL - All data must be in CEDAR format")

# Packages are prepared explicitly from renv.lock. Docker uses its image library;
# native startup may select the copied project library. No runtime installation.

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
library(reactable)
library(bslib)
library(tidyverse)
library(htmlwidgets)
library(htmltools)
library(yaml)
library(qs2)

message("[global.R] Loading shiny_config...")
source("config/shiny_config.R")

# Container deployments default this to INFO in Dockerfile.shiny. Keep the
# local config useful for interactive debugging while allowing operations to
# enforce a quieter level without rewriting the ignored machine-local file.
.cedar_log_level_env <- toupper(trimws(Sys.getenv("CEDAR_LOG_LEVEL", unset = "")))
if (nzchar(.cedar_log_level_env)) {
  if (!.cedar_log_level_env %in% c("DEBUG", "INFO", "WARN", "ERROR")) {
    stop("[global.R] CEDAR_LOG_LEVEL must be DEBUG, INFO, WARN, or ERROR.")
  }
  cedar_log_level <- .cedar_log_level_env
}
rm(.cedar_log_level_env)

message("[global.R] Loading functions...")
source("R/trunk/load-funcs.R")

message("[global.R] Calling load_funcs...")
load_funcs(cedar_base_dir)
CEDAR_SHARED_REQUIREMENTS <- load_degree_shared_requirements(CEDAR_DEGREE_CATALOG,
  cedar_institution_dir())


# if running in a docker container, look for data in the usual data dir
if (is_docker()) {
  data_dir <- "/srv/shiny-server/cedar/data/"
  message("[global.R] Loading data files for Docker environment. Data dir: ", data_dir)

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
#   - cedar_student_terms.qs - One row per student-term: enrolled, returned (ADR-001)
#   - cedar_programs.qs    - Program enrollments
#   - cedar_degrees.qs     - Degrees awarded
#   - cedar_faculty.qs     - Faculty data
#
# data_objects Structure (what cones expect):
#   data_objects[["cedar_sections"]]  - Course sections
#   data_objects[["cedar_students"]]  - Student enrollments
#   data_objects[["cedar_student_terms"]] - One row per student-term (enrolled, returned)
#   data_objects[["cedar_programs"]]  - Program enrollments
#   data_objects[["cedar_degrees"]]   - Degrees awarded
#   data_objects[["cedar_faculty"]]   - Faculty data
#   data_objects[["cedar_dims"]]      - The mapping files as dimension tables (units, colleges, subjects, programs), built at load
#
# Note: Runtime code should use the CEDAR table names above. Short aliases are
#       provided only for analyst convenience in interactive sessions.
#=============================================================================

# CEDAR file list - these are the actual file names on disk
cedar_files <- list(
  cedar_sections   = "cedar_sections",
  cedar_students   = "cedar_students",
  cedar_programs   = "cedar_programs",
  cedar_degrees    = "cedar_degrees",
  cedar_faculty    = "cedar_faculty",
  cedar_grades     = "cedar_grades",     # Pre-classified outcomes (pass/dfw) — speeds up Roadblocks
  cedar_student_terms = "cedar_student_terms", # One row per student-term: enrolled, returned (ADR-001 step 2)
  cedar_applicants = "cedar_applicants"  # Admissions data — used for course impact covariate matching
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
cedar_source_fingerprints <- list()

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
  source_info <- file.info(data_path)
  cedar_source_fingerprints[[key]] <- list(
    path = normalizePath(data_path, mustWork = FALSE),
    size = unname(source_info$size),
    modified = as.character(source_info$mtime)
  )
}

# ── Dimensions and the default unit (ADR-001 step 3) ─────────────────────────
# The mapping files are the dimension tables, read at every start; every unit
# column (department, college, dept_code, college_code, the student-term's
# primary_dept_code, and the crosslist columns that follow a department) is
# attached here, so a mapping edit changes the next start and rebuilds
# nothing. The saved tables carry keys only; a file stamped by an older
# transform loads the same way, its copy dropped first.
#
# Trim first (cedar_min_term, set in shiny_config.R): rows that go are never
# attached, so the attach's transient copy is of the rows the app keeps.
for (.key in c("cedar_sections", "cedar_students", "cedar_grades", "cedar_student_terms", "cedar_faculty", "cedar_degrees", "cedar_programs")) {
  if (!is.null(data_objects[[.key]]) && "term" %in% names(data_objects[[.key]])) {
    .n_before <- nrow(data_objects[[.key]])
    data_objects[[.key]] <- dplyr::filter(data_objects[[.key]], term >= cedar_min_term)
    message(sprintf("[global.R] %s: trimmed to term >= %s (%d -> %d rows)",
                    .key, cedar_min_term, .n_before, nrow(data_objects[[.key]])))
  }
}
rm(.key, .n_before)

cedar_dims <- build_cedar_dims()
data_objects <- attach_default_units(data_objects, cedar_dims)
data_objects[["cedar_dims"]] <- cedar_dims

# The course dimension (ADR-001 step 4): one course_id per code, following the
# confirmed successions in code_history.csv. attach_course_ids() keys the
# sections, the class lists and the grades on it: subject_course is the course
# from here on, and listed_code the code the registrar used that term. Never
# saved: a confirmed row changes it at the next start, as a unit decision does.
cedar_courses <- build_cedar_courses(data_objects[["cedar_sections"]], data_objects[["cedar_students"]], cedar_dims)
data_objects <- attach_course_ids(data_objects, cedar_courses)
data_objects[["cedar_courses"]] <- cedar_courses$courses
data_objects[["cedar_course_codes"]] <- cedar_courses$codes
# The mapping files now decide the unit columns on the attached tables without
# changing any saved file, so they are an input to every cache keyed on those
# tables' fingerprints (caching cardinal rule 1): fold a fingerprint of dims
# into each attached table's, and a mapping edit is a miss.
cedar_dims_hash <- substr(digest::digest(cedar_dims), 1, 12)
for (.key in intersect(names(CEDAR_ATTACHED_UNIT_COLUMNS), names(cedar_source_fingerprints))) {
  cedar_source_fingerprints[[.key]][["dims"]] <- cedar_dims_hash
}
rm(.key)

message("[global.R] Data loading complete. Validating CEDAR data structure...")

# Validate critical CEDAR datasets
# These validations ensure data is in CEDAR format before the app starts
validation_specs <- list(
  cedar_sections = c("section_id", "term", "department", "instructor_id", "subject_course", "part_term"),
  cedar_students = c("student_id", "term", "department", "final_grade", "credits", "subject_code", "level", "instructor_id", "part_term"),
  cedar_programs = c("term", "student_level", "program_type", "program_name", "dept_code", "student_college", "student_campus"),
  cedar_degrees = c("term", "degree", "major_code"),
  cedar_faculty = c("term", "instructor_id", "department", "job_category"),
  cedar_student_terms = c("student_id", "term", "enrolled", "returned_next_regular_term", "return_observable",
                          # the credit position every Pathways credit axis reads
                          "cumulative_attempted_unm_credits", "cumulative_completed_unm_credits",
                          "unm_credits_entering", "timeline_valid")
)

# cedar_student_terms is built by the transform from students, programs and
# degrees (ADR-001 step 2) and the deploy gate rebuilds it whenever one of them
# is newer. An app without it has no definition of enrolled or returned, so it
# does not start: Roadblocks and Course Dynamics retention read nothing else.
if (is.null(data_objects[["cedar_student_terms"]]) ||
    nrow(data_objects[["cedar_student_terms"]]) == 0) {
  stop("[global.R] cedar_student_terms is missing or empty in ", data_dir, ".\n",
       "  Build it with: Rscript --vanilla R/data-parsers/transform-to-cedar.R ",
       "--tables student_terms\n",
       "  (or run scripts/rebuild-programs-if-mappings-changed.R, which builds it ",
       "when it is missing or stale).")
}

validation_failed <- FALSE
for (key in names(validation_specs)) {
  if (!validate_cedar_data(data_objects[[key]], key, validation_specs[[key]])) {
    validation_failed <- TRUE
  }
}

if (validation_failed) {
  stop("[global.R] CEDAR data validation failed. Cannot start application.\n",
       "  Please ensure all data files are in CEDAR format.")
}

message("[global.R] ✅ All CEDAR data validated successfully!")

# ── Data edges ──────────────────────────────────────────────────────────────
# Read once from the loaded data, never derived from cedar_current_term. Local
# data runs behind the registrar and a term arrives in stages — registration
# months early, grades weeks late — so the last enrolled term and the last
# GRADEABLE term are routinely different. Bounding a grade-based rate by the
# enrollment edge produces a confident wrong number: before this existed, the
# DFW rate for the newest term read 0.3% against 6-8% for every other term,
# because the denominator counted every attempt while the numerator saw only
# the handful of grades that had posted. The cache-warming scripts call the
# same function, so the caches they write match what the app asks for. See the
# right-edge policy in AGENTS.md.
.report_edges <- cedar_report_edges(
  data_objects[["cedar_students"]],
  degrees = data_objects[["cedar_degrees"]]
)
cedar_edges <- .report_edges$edges
data_objects[["cedar_edges"]] <- cedar_edges
# Anything that reads a grade.
cedar_graded_through <- .report_edges$graded_through
# Settled enrollment reporting, trend comparisons and longitudinal follow-up:
# the last term whose registration has settled, so an in-flight term does not
# read as a collapse.
cedar_report_end_term <- .report_edges$report_end_term
# The newest term with any registrations. Descriptive enrollment charts (Dept
# Trends headcount, course enrollment, attempted SCH) run to here and label the
# terms after the graded edge as in progress -- see cedar_in_progress_terms().
cedar_report_latest_term <- .report_edges$report_latest_term
rm(.report_edges)
# The term dimension (ADR-001 step 1): one row per term in the loaded data,
# the edges above as per-term flags, the next and previous regular terms, and
# each term's first day and census date read from its sections. A reader may
# bound an analysis with filter(is_settled) instead of comparing against the
# globals above; the flags are the same edges, passed in, never recomputed.
cedar_terms <- build_cedar_terms(
  data_objects[["cedar_students"]],
  sections = data_objects[["cedar_sections"]],
  degrees  = data_objects[["cedar_degrees"]],
  edges    = cedar_edges
)
data_objects[["cedar_terms"]] <- cedar_terms
message(sprintf("[global.R] cedar_terms: %d terms, %s to %s", nrow(cedar_terms),
                cedar_terms$label[[1]], cedar_terms$label[[nrow(cedar_terms)]]))

# Pre-compute stable source hashes for cache keys. Each combines the loaded
# dimensions with file size and modification time, so a same-shape replacement
# still invalidates. Stored as globals so cache lookups do not touch large data.
cedar_students_hash <- cedar_cache_object_hash(
  data_objects[["cedar_students"]], cedar_source_fingerprints[["cedar_students"]]
)
cedar_sections_hash <- cedar_cache_object_hash(
  data_objects[["cedar_sections"]], cedar_source_fingerprints[["cedar_sections"]]
)
cedar_programs_hash <- cedar_cache_object_hash(
  data_objects[["cedar_programs"]], cedar_source_fingerprints[["cedar_programs"]]
)
cedar_degrees_hash <- cedar_cache_object_hash(
  data_objects[["cedar_degrees"]], cedar_source_fingerprints[["cedar_degrees"]]
)
cedar_faculty_hash <- cedar_cache_object_hash(
  data_objects[["cedar_faculty"]], cedar_source_fingerprints[["cedar_faculty"]]
)
# Dept Trends uses content hashes, prepared once so individual tab requests
# never rescan source tables or invalidate just because a file was rewritten.
cedar_dept_source_hashes <- hash_dept_cache_sources(data_objects)
message(sprintf(
  paste0("[global.R] Cache hashes: students=%s sections=%s programs=%s ",
         "degrees=%s faculty=%s"),
  cedar_students_hash, cedar_sections_hash, cedar_programs_hash,
  cedar_degrees_hash, cedar_faculty_hash
))

message("[global.R] Data objects ready:")
message("  - cedar_sections: ", nrow(data_objects[["cedar_sections"]]), " rows")
message("  - cedar_students: ", nrow(data_objects[["cedar_students"]]), " rows")
message("  - cedar_student_terms: ", nrow(data_objects[["cedar_student_terms"]]), " rows")
message("  - cedar_programs: ", nrow(data_objects[["cedar_programs"]]), " rows")
message("  - cedar_degrees: ", nrow(data_objects[["cedar_degrees"]]), " rows")
message("  - cedar_faculty: ", nrow(data_objects[["cedar_faculty"]]), " rows")
} # end data loading for docker

# ── cedar_attempts: one classified outcome per graded attempt (ADR-001 step 4)
# build_attempts() (R/branches/attempts.R) classifies the keyed class list
# once, up to the graded edge, so readers share one pass/DFW/withdrawal answer
# per attempt. Held at data_objects[["cedar_attempts"]] and passed to readers;
# the copy saved beside the data is a cache, used only when it is newer than
# the class list and attempts_is_current() finds this build, outcome policy,
# graded edge and the class list's renames on it.
if (!is.null(data_objects[["cedar_students"]]) && nrow(data_objects[["cedar_students"]]) > 0) {
  attempts_path    <- file.path(data_dir, "cedar_attempts.qs")
  students_qs_path <- file.path(data_dir, paste0("cedar_students", get_data_extension()))
  saved_is_newer <- file.exists(attempts_path) && file.exists(students_qs_path) &&
                    file.info(attempts_path)$mtime > file.info(students_qs_path)$mtime
  saved_attempts <- NULL
  if (saved_is_newer) {
    saved_attempts <- tryCatch(qs2::qs_read(attempts_path), error = function(e) {
      message("[global.R] Saved cedar_attempts unreadable: ", conditionMessage(e))
      NULL
    })
  }
  if (attempts_is_current(saved_attempts, data_objects[["cedar_students"]], cedar_edges)) {
    data_objects[["cedar_attempts"]] <- saved_attempts
    message(sprintf("[global.R] cedar_attempts loaded: %d rows", nrow(saved_attempts)))
  } else {
    if (saved_is_newer) {
      message("[global.R] Saved cedar_attempts is from another build, policy, edge or course codes; rebuilding.")
    }
    t_at <- system.time({
      data_objects[["cedar_attempts"]] <- build_attempts(data_objects[["cedar_students"]], cedar_edges)
    })
    message(sprintf("[global.R] cedar_attempts built: %d rows (%.1fs)",
                    nrow(data_objects[["cedar_attempts"]]), t_at["elapsed"]))
    tryCatch({
      tmp_path <- paste0(attempts_path, ".tmp")
      qs2::qs_save(data_objects[["cedar_attempts"]], tmp_path)
      file.rename(tmp_path, attempts_path)
      message("[global.R] cedar_attempts saved.")
    }, error = function(e) {
      message("[global.R] Warning: failed to save cedar_attempts: ", e$message)
    })
  }
  rm(saved_attempts)
}

# ── cedar_course_terms: the course-term measure table (ADR-001 step 4) ──────
# build_course_terms() (R/branches/course-terms.R) counts the keyed class list
# once by course, term, campus and part of term, so Regstats, the Department
# Dashboard and Waitlists filter a small table instead of recounting millions
# of rows on every request. It is held at data_objects[["cedar_course_terms"]]
# and passed to each reader. The copy saved beside the data is a cache only:
# it is used when it is newer than the class list and course_terms_is_current()
# finds this build's version and columns and the class list's renames on it;
# otherwise it is rebuilt.
if (!is.null(data_objects[["cedar_students"]]) && nrow(data_objects[["cedar_students"]]) > 0) {
  course_terms_path <- file.path(data_dir, "cedar_course_terms.qs")
  students_qs_path  <- file.path(data_dir, paste0("cedar_students", get_data_extension()))
  saved_is_newer <- file.exists(course_terms_path) &&
                    file.exists(students_qs_path) &&
                    file.info(course_terms_path)$mtime > file.info(students_qs_path)$mtime

  saved_course_terms <- NULL
  if (saved_is_newer) {
    saved_course_terms <- tryCatch(qs2::qs_read(course_terms_path), error = function(e) {
      message("[global.R] Saved cedar_course_terms unreadable: ", conditionMessage(e))
      NULL
    })
  }
  if (course_terms_is_current(saved_course_terms, data_objects[["cedar_students"]],
                              graded_edge = cedar_edges$last_graded)) {
    data_objects[["cedar_course_terms"]] <- saved_course_terms
    message(sprintf("[global.R] cedar_course_terms loaded: %d rows",
                    nrow(saved_course_terms)))
  } else {
    if (saved_is_newer) {
      message("[global.R] Saved cedar_course_terms is from another build, graded edge or course codes; rebuilding.")
    }
    t_ct <- system.time({
      data_objects[["cedar_course_terms"]] <- build_course_terms(data_objects[["cedar_students"]],
                                                                 data_objects[["cedar_attempts"]])
    })
    message(sprintf("[global.R] cedar_course_terms built: %d rows (%.1fs)",
                    nrow(data_objects[["cedar_course_terms"]]), t_ct["elapsed"]))
    tryCatch({
      tmp_path <- paste0(course_terms_path, ".tmp")
      qs2::qs_save(data_objects[["cedar_course_terms"]], tmp_path)
      file.rename(tmp_path, course_terms_path)
      message("[global.R] cedar_course_terms saved.")
    }, error = function(e) {
      message("[global.R] Warning: failed to save cedar_course_terms: ", e$message)
    })
  }
  rm(saved_course_terms)
}

# ── Pre-compute campus-scoped course pair flow table for downstream signals ───
# get_next_course_pairs() owns the course-sequencing methodology. Precomputing
# it once keeps Regstats fast while preserving the same campus-scoped join policy
# used by Course Dynamics.
# Invalidated automatically when cedar_students.qs changes. The v2 filename
# avoids loading older cache files that did not include campus in the schema.
# Counted over the loaded class list, which is keyed on the course, so a pair
# follows each course across its codes; the renames it was counted over are
# stamped on it and checked here, so a confirmed code_history.csv row (or a
# file counted by code) is recomputed rather than read.
cedar_course_flows <- tryCatch({
  if (is.null(data_objects[["cedar_students"]]) || nrow(data_objects[["cedar_students"]]) == 0) {
    NULL
  } else {
    flows_cache_path  <- file.path(data_dir, "cedar_course_flows_v2.qs")
    students_qs_path  <- file.path(data_dir, paste0("cedar_students", get_data_extension()))
    flows_cache_valid <- file.exists(flows_cache_path) &&
                         file.exists(students_qs_path) &&
                         file.info(flows_cache_path)$mtime > file.info(students_qs_path)$mtime

    students_renames <- course_code_renames(data_objects[["cedar_students"]])
    cached_flows <- if (flows_cache_valid) qs2::qs_read(flows_cache_path) else NULL
    if (!is.null(cached_flows) &&
        !identical(attr(cached_flows, "code_renames", exact = TRUE), students_renames)) {
      message("[global.R] Cached course pair flows were counted over other course codes; recomputing.")
      cached_flows <- NULL
    }

    if (!is.null(cached_flows)) {
      message(sprintf("[global.R] Course flows loaded: %d rows", nrow(cached_flows)))
      cached_flows
    } else {
      message("[global.R] Pre-computing course pair flows for downstream signals...")
      t_flows <- system.time({
        result <- get_next_course_pairs(data_objects[["cedar_students"]], opt = list(summer = FALSE))
        attr(result, "code_renames") <- students_renames
      })
      message(sprintf("[global.R] Course flows ready: %d rows (%.1fs)",
                      nrow(result), t_flows["elapsed"]))
      tryCatch(
        { qs2::qs_save(result, flows_cache_path)
          message("[global.R] Course flows cached to disk.") },
        error = function(e) message("[global.R] Warning: Failed to cache course flows: ", e$message)
      )
      result
    }
  }
}, error = function(e) {
  message("[global.R] Warning: course pair flow pre-computation failed: ", e$message,
          " — downstream signals will be unavailable.")
  NULL
})

# ── Pre-compute data summary for Data & Usage page ─────────────────────────
# This avoids expensive reactive computations and makes the tab load instantly
message("[global.R] Pre-computing data summary...")

# Helper: per-term last-update dates for a dataset → named list(term_code = date_str)
.term_dates <- function(data) {
  if (is.null(data) || nrow(data) == 0) return(setNames(list(), character(0)))
  terms <- sort(unique(data[["term"]]), decreasing = TRUE)
  dates <- vapply(terms, function(t) {
    as.character(max(data[["as_of_date"]][data[["term"]] == t], na.rm = TRUE))
  }, character(1))
  setNames(as.list(dates), as.character(terms))
}

# Helper: choose which terms to display and in what order:
#   current | future summers (asc) | future non-summers (asc) | previous terms (desc)
#   Summers are shown but don't consume one of the 2 "previous" non-summer slots.
.select_display_terms <- function(available_terms, current_term) {
  available_terms <- as.integer(available_terms)
  is_summer <- function(t) (as.integer(t) %% 100L) == 60L
  non_sum <- sort(available_terms[!is_summer(available_terms)], decreasing = TRUE)
  summers <- sort(available_terms[ is_summer(available_terms)], decreasing = TRUE)
  next_ns   <- head(non_sum[non_sum >  current_term], 1L)
  curr_prev <- head(non_sum[non_sum <= current_term], 3L)   # current + 2 prev
  low  <- if (length(curr_prev) == 3L) curr_prev[3L] else 0L
  high <- if (length(next_ns)  == 1L) next_ns else Inf
  rel_sum <- summers[summers > low & summers < high]
  selected <- unique(as.integer(c(next_ns, curr_prev, rel_sum)))
  # Reorder: current first, then futures (summers then non-summers, nearest first), then prev desc
  curr    <- selected[selected == current_term]
  futures <- sort(selected[selected > current_term], decreasing = FALSE)
  fut_sum <- futures[ is_summer(futures)]
  fut_ns  <- futures[!is_summer(futures)]
  prev    <- sort(selected[selected < current_term], decreasing = TRUE)
  c(curr, fut_sum, fut_ns, prev)
}

# Helper: short human-readable term label with (next)/(curr) annotation
.term_label <- function(t) {
  t <- as.integer(t)
  yr <- t %/% 100L; ss <- t %% 100L
  season <- if (ss == 10L) "Sp" else if (ss == 80L) "Fa" else if (ss == 60L) "Su" else paste0("T", ss)
  paste0(season, " ", yr)
}

cedar_data_summary <- list()

# Sections
if (!is.null(data_objects[["cedar_sections"]]) && nrow(data_objects[["cedar_sections"]]) > 0) {
  cedar_data_summary$sections_count      <- nrow(data_objects[["cedar_sections"]])
  cedar_data_summary$sections_term_dates <- .term_dates(data_objects[["cedar_sections"]])
} else {
  cedar_data_summary$sections_count      <- 0L
  cedar_data_summary$sections_term_dates <- list()
}

# Students
if (!is.null(data_objects[["cedar_students"]]) && nrow(data_objects[["cedar_students"]]) > 0) {
  cedar_data_summary$students_count      <- nrow(data_objects[["cedar_students"]])
  cedar_data_summary$students_term_dates <- .term_dates(data_objects[["cedar_students"]])
  cedar_data_summary$students_status_dates <- class_list_status_date_coverage(data_objects[["cedar_students"]])
} else {
  cedar_data_summary$students_count      <- 0L
  cedar_data_summary$students_term_dates <- list()
}

# Programs
if (!is.null(data_objects[["cedar_programs"]]) && nrow(data_objects[["cedar_programs"]]) > 0) {
  cedar_data_summary$programs_count      <- nrow(data_objects[["cedar_programs"]])
  cedar_data_summary$programs_term_dates <- .term_dates(data_objects[["cedar_programs"]])
} else {
  cedar_data_summary$programs_count      <- 0L
  cedar_data_summary$programs_term_dates <- list()
}

# Degrees
if (!is.null(data_objects[["cedar_degrees"]]) && nrow(data_objects[["cedar_degrees"]]) > 0) {
  cedar_data_summary$degrees_count      <- nrow(data_objects[["cedar_degrees"]])
  cedar_data_summary$degrees_term_dates <- .term_dates(data_objects[["cedar_degrees"]])
} else {
  cedar_data_summary$degrees_count      <- 0L
  cedar_data_summary$degrees_term_dates <- list()
}

# Faculty
if (!is.null(data_objects[["cedar_faculty"]]) && nrow(data_objects[["cedar_faculty"]]) > 0) {
  cedar_data_summary$faculty_count      <- nrow(data_objects[["cedar_faculty"]])
  cedar_data_summary$faculty_term_dates <- .term_dates(data_objects[["cedar_faculty"]])
} else {
  cedar_data_summary$faculty_count      <- 0L
  cedar_data_summary$faculty_term_dates <- list()
}

# Determine display terms: next + current + prev 2 non-summer + relevant summers
all_data_terms <- unique(unlist(lapply(
  c("cedar_sections","cedar_students","cedar_programs","cedar_degrees","cedar_faculty"),
  function(k) if (!is.null(data_objects[[k]])) data_objects[[k]][["term"]] else integer(0)
)))
cedar_data_summary$display_terms <- .select_display_terms(all_data_terms, cedar_current_term)

configured_default_term <- if (exists("cedar_default_term", inherits = FALSE)) {
  cedar_default_term
} else {
  NULL
}
cedar_default_term <- resolve_default_term_choice(
  all_data_terms,
  default_term = configured_default_term,
  fallback_term = cedar_current_term
)

# Human-readable label for the current term (e.g. 202610 → "Spring 2026")
cedar_current_term_label <- local({
  t  <- as.integer(cedar_current_term)
  yr <- t %/% 100L; ss <- t %% 100L
  season <- switch(as.character(ss), "10" = "Spring", "80" = "Fall", "60" = "Summer",
                   paste0("Term ", ss))
  paste0(season, " ", yr)
})

cedar_default_term_label <- if (!is.null(cedar_default_term)) {
  term_code_to_str(cedar_default_term)
} else {
  NULL
}

# Shared default term for registration-facing tabs. This intentionally follows
# cedar_default_term so every term picker opens on the same configured term.
cedar_default_reg_term <- as.character(cedar_default_term)

# Pathways population selectors use small choice lists derived from the large
# cedar_programs table. Build them once at startup so each browser session does
# not scan the full program history before the Majors input becomes searchable.
cedar_pathways_choices <- pathways_population_choice_lists(data_objects[["cedar_programs"]])
message("[global.R] Pathways choices ready: ",
        length(cedar_pathways_choices$program_choices), " programs, ",
        length(cedar_pathways_choices$dept_choices), " departments")

# Timestamp when computed
cedar_data_summary$computed_at <- Sys.time()

message("[global.R] ✓ Data summary computed: ",
        length(cedar_data_summary$display_terms), " display terms (",
        paste(cedar_data_summary$display_terms, collapse = ", "), ")")

# Initialize logging system
message("[global.R] Initializing logging system...")
init_logging()

message("[global.R] Loading ui.R and server.R...")
source("ui.R")
source("server.R")
