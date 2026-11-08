# Deploy-time gate: build the derived tables the app cannot start without,
# when they are missing or stale.
#
#   Rscript --vanilla scripts/rebuild-programs-if-mappings-changed.R [--force]
#
# The name is historical: deploy.yml and update-data.sh call it by it. Until
# ADR-001 step 3 (2026-11-06) it also rebuilt whichever of programs, degrees,
# sections and class lists had been built from different mapping files, each
# carrying a provenance stamp (ISSUES.md M26). The fact tables no longer store
# a unit: the loader attaches every one at start from the mapping files
# (R/branches/dims.R), so a mapping edit changes the next start and rebuilds
# none of them, and that branch is gone.
#
# What remains are the derived tables, each built in its own R process here,
# before the first request, because the app requires them and never builds
# one (ADR-001 step 6: a restart is a load):
#
# - cedar_student_terms (step 2), built from the saved students, programs and
#   degrees: stale whenever one of them is newer, short a column the builder
#   now writes, or built under an older rule version
#   (cedar_student_terms_staleness()).
# - the measure tables cedar_attempts, cedar_course_terms and
#   cedar_course_flows (step 6), built from the saved class list over the
#   mapping files: stale whenever the class list is newer, a builder's version,
#   the outcome policy or the columns changed, the mapping files changed (their
#   unit columns are the files'), or the app's first term changed
#   (cedar_measures_staleness()). So a mapping PR rebuilds them here, in
#   minutes, and the app that then starts only loads.
#
# Checked by file times and the saved files' names and stamps, never by
# loading the class list, so a deploy that changed nothing costs seconds.
# Data-driven staleness stays with the morning refresh, whose transform
# builds every derived table after the fact tables. `force` rebuilds them
# regardless.
rebuild_programs_if_mappings_changed <- function(
    data_dir = NULL, base_dir = getwd(), rebuild = NULL, force = FALSE) {
  SOURCED_FROM_PARSE_DATA <<- TRUE
  source(file.path(base_dir, "config", "config.R"))
  source(file.path(base_dir, "R", "trunk", "load-funcs.R"))
  load_funcs(base_dir, modules = FALSE)
  source(file.path(base_dir, "R", "data-parsers", "transform-to-cedar.R"))
  # The measure tables start at the app's first term, a setting in the app's
  # config; read that one value without the file's other side effects.
  shiny_settings <- new.env()
  sys.source(file.path(base_dir, "config", "shiny_config.R"), envir = shiny_settings)
  if (!exists("cedar_min_term", envir = shiny_settings, inherits = FALSE)) {
    stop("[gate] config/shiny_config.R defines no cedar_min_term; the measure tables need it.",
         call. = FALSE)
  }
  min_term <- get("cedar_min_term", envir = shiny_settings)

  is_docker <- Sys.getenv("docker") == "TRUE" || file.exists("/.dockerenv")
  if (is.null(data_dir)) {
    data_dir <- if (is_docker && exists("cedar_data_docker_dir")) {
      cedar_data_docker_dir
    } else if (exists("cedar_shared_data_dir")) {
      cedar_shared_data_dir
    } else {
      "data/"
    }
  }
  # Each stage is built in its own R process. The transform keeps every
  # stage's heap until it exits, so one process running the four fact tables
  # and then the student-term stage was killed for memory on an 8.6 GB
  # development host while anything else ran beside it (2026-11-04); the
  # student-term stage alone peaks at about 1.6 GB.
  rebuild <- rebuild %||% function(tables) {
    script <- file.path(base_dir, "R", "data-parsers", "transform-to-cedar.R")
    for (table in tables) {
      message("[gate] Rebuilding the ", table, " stage in its own R process...")
      status <- system2(
        file.path(R.home("bin"), "Rscript"),
        c("--vanilla", shQuote(script), "--data-dir", shQuote(data_dir), "--tables", table))
      if (!identical(as.integer(status), 0L)) {
        stop("[gate] The rebuild of the ", table, " stage exited with status ", status,
             call. = FALSE)
      }
    }
  }

  built_student_terms <- build_student_terms_if_stale(data_dir, rebuild, force = force)
  built_measures <- build_measures_if_stale(
    data_dir, rebuild, force = force,
    staleness = function(dir) cedar_measures_staleness(dir, min_term = min_term))
  invisible(built_student_terms || built_measures)
}

#' The gate's decision for the measure tables: build them when stale or forced
#'
#' @param data_dir The directory holding the saved tables.
#' @param rebuild A function taking the stages to build (here always
#'   `"measures"`), run once when a build is due.
#' @param force Build regardless of staleness.
#' @param staleness The check, as a function of `data_dir` (here
#'   cedar_measures_staleness() with the app's first term); a parameter so the
#'   decision can be tested without one.
#' @return TRUE when the tables were built, FALSE when they were current; an
#'   error when a build left one stale.
build_measures_if_stale <- function(data_dir, rebuild, force = FALSE, staleness) {
  reason <- if (isTRUE(force)) "rebuild forced" else staleness(data_dir)
  if (is.null(reason)) {
    message("[measures] The measure tables are current; no rebuild. ",
            "Data-driven staleness is handled by the morning refresh.")
    return(invisible(FALSE))
  }
  message("[measures] Rebuilding the measure tables: ", reason)
  rebuild("measures")
  still <- staleness(data_dir)
  if (!is.null(still)) {
    stop("[measures] Rebuilt, but a measure table is still stale: ", still, call. = FALSE)
  }
  # deploy.yml restarts the app on this exact line, so it serves what was built.
  message("[measures] Rebuilt: ", paste(CEDAR_MEASURE_TABLES, collapse = ", "), ".")
  invisible(TRUE)
}

#' The gate's decision: build cedar_student_terms when stale or forced
#'
#' @param data_dir The directory holding the saved tables.
#' @param rebuild A function taking the tables to build (here always
#'   `"student_terms"`), run once when a build is due.
#' @param force Build regardless of staleness.
#' @param staleness The check (cedar_student_terms_staleness(), from the
#'   transform); a parameter so the decision can be tested without one.
#' @return TRUE when the table was built, FALSE when it was current; an error
#'   when a build left it stale.
build_student_terms_if_stale <- function(data_dir, rebuild, force = FALSE,
                                         staleness = cedar_student_terms_staleness) {
  reason <- if (isTRUE(force)) "rebuild forced" else staleness(data_dir)
  if (is.null(reason)) {
    message("[student-terms] cedar_student_terms is current; no rebuild. ",
            "Data-driven staleness is handled by the morning refresh.")
    return(invisible(FALSE))
  }
  message("[student-terms] Rebuilding cedar_student_terms: ", reason)
  rebuild("student_terms")
  still <- staleness(data_dir)
  if (!is.null(still)) {
    stop("[student-terms] Rebuilt, but cedar_student_terms is still stale: ", still, call. = FALSE)
  }
  # deploy.yml restarts the app on this exact line, so it serves what was built.
  message("[student-terms] Rebuilt: cedar_student_terms.")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  rebuild_programs_if_mappings_changed(
    force = "--force" %in% commandArgs(trailingOnly = TRUE)
  )
}
