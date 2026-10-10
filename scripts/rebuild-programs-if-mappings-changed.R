# Deploy-time gate: rebuild the mapped CEDAR tables when the MAPPING source moved.
#
#   Rscript --vanilla scripts/rebuild-programs-if-mappings-changed.R [--force]
#
# Same shape as the enrollment-projection model gate, and for the same reason.
# Units are written at transform time, so editing a mapping file changes
# nothing until the tables are rebuilt -- and nothing says the two have
# drifted, because the stored units stay plausible. A mapping fix can sit in
# the repository while production serves the old departments.
#
# Since ADR-002 Stage 3 the files decide every unit: programs.csv for programs
# and degrees, subjects.csv for sections and class lists. Each of those tables
# carries the provenance that built it, and the gate rebuilds whichever are
# stale (CEDAR_MAPPED_TABLES; ISSUES.md M26). The name is historical: deploy.yml
# and update-data.sh call it by it.
#
# The check is cheap on purpose: it hashes the mapping files and reads one
# attribute per table, so a deploy that changed no mapping costs seconds.
# Data-driven staleness stays with the morning refresh.

# The stamp asserts "these units were produced by this mapping source".
# `force` rebuilds every mapped table regardless. (Until ADR-002 Stage 4 this
# also regenerated program_map.qs; the map is retired.)
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
  stale <- if (isTRUE(force)) {
    stats::setNames(rep("rebuild forced", length(CEDAR_MAPPED_TABLES)), CEDAR_MAPPED_TABLES)
  } else {
    cedar_stale_mapped_tables(data_dir, base_dir)
  }
  if (length(stale) == 0) {
    message("[mappings] Mapping source unchanged since ",
            paste0("cedar_", CEDAR_MAPPED_TABLES, collapse = ", "),
            " were built; no rebuild. Data-driven staleness is handled by the morning refresh.")
    return(invisible(FALSE))
  }
  for (table in names(stale)) {
    message("[mappings] Rebuilding cedar_", table, ": ", stale[[table]])
  }

  # A missing export would make the transform skip the table with a warning,
  # leaving it stale while this gate reported a rebuild. Stop instead.
  inputs <- c(programs = "academic_studies", degrees = "degrees",
              sections = "DESRs", students = "class_lists")
  needed <- file.path(data_dir, paste0(inputs[names(stale)], ".qs"))
  if (any(!file.exists(needed))) {
    stop("[mappings] Cannot rebuild ", paste0("cedar_", names(stale)[!file.exists(needed)], collapse = ", "),
         ": missing ", paste(basename(needed[!file.exists(needed)]), collapse = ", "),
         " in ", data_dir, call. = FALSE)
  }

  rebuild <- rebuild %||% function(tables) transform_to_cedar(data_dir = data_dir,
                                                             tables = tables)
  rebuild(names(stale))
  still <- intersect(names(stale), names(cedar_stale_mapped_tables(data_dir, base_dir)))
  if (length(still)) {
    stop("[mappings] Rebuilt, but still stale: ", paste0("cedar_", still, collapse = ", "),
         call. = FALSE)
  }
  message("[mappings] Rebuilt: ", paste0("cedar_", names(stale), collapse = ", "), ".")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  rebuild_programs_if_mappings_changed(
    force = "--force" %in% commandArgs(trailingOnly = TRUE)
  )
}
