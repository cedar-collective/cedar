# Deploy-time gate: build cedar_student_terms when it is missing or stale.
#
#   Rscript --vanilla scripts/rebuild-programs-if-mappings-changed.R [--force]
#
# The name is historical: deploy.yml and update-data.sh call it by it. Until
# ADR-001 step 3 (2026-11-06) it also rebuilt whichever of programs, degrees,
# sections and class lists had been built from different mapping files, each
# carrying a provenance stamp (ISSUES.md M26). The tables no longer store a
# unit: the loader attaches every one at start from the mapping files
# (R/branches/dims.R), so a mapping edit changes the next start and rebuilds
# nothing, and that branch is gone.
#
# What remains is cedar_student_terms (ADR-001 step 2). It is built from the
# saved students, programs and degrees, so it is stale whenever one of them is
# newer, short a column the builder now writes, or built under an older rule
# version, and absent on the first deploy after the stage was added. The app
# requires it, so the gate builds it here, in its own R process, before the
# first request. Checked by file time and the saved file's names and stamp
# (cedar_student_terms_staleness()), never by loading the sources, so a deploy
# that changed nothing costs about a second. Data-driven staleness stays with
# the morning refresh. `force` rebuilds the table regardless.
rebuild_programs_if_mappings_changed <- function(
    data_dir = NULL, base_dir = getwd(), rebuild = NULL, force = FALSE) {
  SOURCED_FROM_PARSE_DATA <<- TRUE
  source(file.path(base_dir, "config", "config.R"))
  source(file.path(base_dir, "R", "trunk", "load-funcs.R"))
  load_funcs(base_dir, modules = FALSE)
  source(file.path(base_dir, "R", "data-parsers", "transform-to-cedar.R"))

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
  # The table is built in its own R process. The transform keeps every
  # stage's heap until it exits, so one process running the four fact tables
  # and then the student-term stage was killed for memory on an 8.6 GB
  # development host while anything else ran beside it (2026-11-04); the
  # stage alone peaks at about 1.6 GB.
  rebuild <- rebuild %||% function(tables) {
    script <- file.path(base_dir, "R", "data-parsers", "transform-to-cedar.R")
    for (table in tables) {
      message("[student-terms] Rebuilding cedar_", table, " in its own R process...")
      status <- system2(
        file.path(R.home("bin"), "Rscript"),
        c("--vanilla", shQuote(script), "--data-dir", shQuote(data_dir), "--tables", table))
      if (!identical(as.integer(status), 0L)) {
        stop("[student-terms] The rebuild of cedar_", table, " exited with status ", status,
             call. = FALSE)
      }
    }
  }

  build_student_terms_if_stale(data_dir, rebuild, force = force)
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
