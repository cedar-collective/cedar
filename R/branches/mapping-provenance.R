# mapping-provenance.R — did the mapping source change since cedar_programs was built?
#
# cedar_programs$dept_code is derived at transform time from the mapping lists
# and program_map.qs. Editing a list therefore changes nothing until the table is
# rebuilt, and nothing announces that the two have drifted apart: the stored
# dept_code stays plausible, and every report keeps using it.
#
# That gap is how a mapping fix sat in the repository while production served the
# old departments. It is the same problem the enrollment-projection model gate
# solves, and this is deliberately the same shape: hash the source that decides
# the answer, stamp it onto the artifact, and compare later.
#
# What this is NOT: a check on whether the DATA changed. New MyReports extracts
# are the morning refresh's job. This answers only "was this table built by the
# mapping code that is deployed now?"

#' Files whose content decides the stored units and colleges
#'
#' The institution mapping files plus the code that reads them into the CEDAR
#' tables (ADR-002). A change to any of them can move a student or a course
#' between departments or colleges.
cedar_mapping_source_files <- function() {
  c(
    "R/lists/subj_dept_map.R",
    "R/lists/institution_files.R",
    file.path("institution", cedar_institution_id(), "colleges.csv"),
    file.path("institution", cedar_institution_id(), "units.csv"),
    file.path("institution", cedar_institution_id(), "subjects.csv"),
    # Read by the transform from ADR-002 Stage 3: it decides every program's unit.
    file.path("institution", cedar_institution_id(), "programs.csv"),
    "R/lists/mappings.R",
    "R/lists/catalog_lookups.R",
    "R/data-parsers/transform-to-cedar.R"
  )
}


#' Fingerprint of the current mapping source
#'
#' @param base_dir Repository root, or anywhere beneath it.
#' @return A list with `files` (per-file sha256) and `combined` (one hash).
cedar_mapping_provenance <- function(base_dir = getwd()) {
  root <- normalizePath(base_dir, mustWork = TRUE)
  while (!file.exists(file.path(root, "global.R")) && dirname(root) != root) {
    root <- dirname(root)
  }
  if (!file.exists(file.path(root, "global.R"))) {
    stop("[mapping-provenance.R] Could not find the CEDAR repository root.",
         call. = FALSE)
  }
  files <- cedar_mapping_source_files()
  paths <- file.path(root, files)
  missing <- files[!file.exists(paths)]
  if (length(missing) > 0) {
    stop("[mapping-provenance.R] Mapping source is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  hashes <- stats::setNames(vapply(paths, function(path) {
    digest::digest(paste(readLines(path, warn = FALSE, encoding = "UTF-8"),
                         collapse = "\n"),
                   algo = "sha256", serialize = FALSE)
  }, character(1)), files)

  list(
    files = as.list(hashes),
    combined = digest::digest(paste(hashes, collapse = "|"),
                              algo = "sha256", serialize = FALSE)
  )
}


# The tables whose units the mapping files decide (ADR-002 Stage 3), each
# stamped by the transform with the provenance that built it. The rebuild gate
# checks every one: a subject decision moves course units as surely as a
# program decision moves program units (ISSUES.md M26).
CEDAR_MAPPED_TABLES <- c("programs", "degrees", "sections", "students")


#' Has the mapping source moved since a CEDAR table was built?
#'
#' Reads only the stamped attribute, never a CEDAR table, so it is cheap enough
#' to run on every deploy.
#'
#' @param table_file Path to the table's .qs file.
#' @param base_dir Repository root.
#' @param table The table's name, for the reason: "cedar_programs".
#' @return NULL when current, otherwise a human-readable reason. Anything
#'   unreadable or unstamped counts as drift: rebuilding costs minutes, while
#'   serving units built by unknown code is how a stale map went unnoticed for
#'   nine months.
cedar_table_mapping_drift <- function(table_file, base_dir = getwd(), table = "cedar_programs") {
  if (!file.exists(table_file)) {
    return(paste("no", table, "at", table_file))
  }
  stamped <- tryCatch(
    attr(qs2::qs_read(table_file), "cedar_mapping_provenance"),
    error = function(e) e
  )
  if (inherits(stamped, "error")) {
    return(paste(table, "is unreadable:", conditionMessage(stamped)))
  }
  if (is.null(stamped)) {
    return(paste(table, "predates mapping-provenance tracking"))
  }

  current <- cedar_mapping_provenance(base_dir)
  if (identical(stamped$combined, current$combined)) return(NULL)

  # Name the files, not just the fact. A deploy log saying "mappings changed"
  # sends someone diffing five files by hand.
  changed <- names(current$files)[!vapply(names(current$files), function(file) {
    identical(stamped$files[[file]], current$files[[file]])
  }, logical(1))]
  added <- setdiff(names(current$files), names(stamped$files))
  removed <- setdiff(names(stamped$files), names(current$files))
  changed <- unique(c(changed, added, removed))
  paste("mapping source changed:", paste(sort(changed), collapse = ", "))
}

#' Has the mapping source moved since cedar_programs was built?
#'
#' cedar_table_mapping_drift() for cedar_programs, which Admin > Data & Usage
#' reports as the mapping freshness.
cedar_programs_mapping_drift <- function(programs_file, base_dir = getwd()) {
  cedar_table_mapping_drift(programs_file, base_dir, "cedar_programs")
}

#' Which mapped tables in a data directory are stale?
#'
#' @param data_dir The directory holding cedar_<table>.qs.
#' @param base_dir Repository root.
#' @return A named character vector: for each table in CEDAR_MAPPED_TABLES that
#'   needs a rebuild, the reason. Empty when all are current.
cedar_stale_mapped_tables <- function(data_dir, base_dir = getwd()) {
  reasons <- vapply(CEDAR_MAPPED_TABLES, function(table) {
    cedar_table_mapping_drift(file.path(data_dir, paste0("cedar_", table, ".qs")),
                              base_dir, paste0("cedar_", table)) %||% NA_character_
  }, character(1))
  reasons[!is.na(reasons)]
}
