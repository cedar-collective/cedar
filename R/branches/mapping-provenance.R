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

#' Files whose content decides cedar_programs$dept_code
#'
#' Institution configuration plus the transform logic that consumes it. A change
#' to any of them can move a student between departments.
cedar_mapping_source_files <- function() {
  c(
    "R/lists/subj_dept_map.R",
    "R/lists/program_code_maps.R",
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


#' Has the mapping source moved since cedar_programs was built?
#'
#' Reads only the stamped attribute, never a CEDAR table, so it is cheap enough
#' to run on every deploy.
#'
#' @param programs_file Path to cedar_programs.qs.
#' @param base_dir Repository root.
#' @return NULL when current, otherwise a human-readable reason. Anything
#'   unreadable or unstamped counts as drift: rebuilding costs minutes, while
#'   serving departments built by unknown code is how this went unnoticed for
#'   nine months.
cedar_programs_mapping_drift <- function(programs_file, base_dir = getwd()) {
  if (!file.exists(programs_file)) {
    return(paste("no cedar_programs at", programs_file))
  }
  stamped <- tryCatch(
    attr(qs2::qs_read(programs_file), "cedar_mapping_provenance"),
    error = function(e) e
  )
  if (inherits(stamped, "error")) {
    return(paste("cedar_programs is unreadable:", conditionMessage(stamped)))
  }
  if (is.null(stamped)) {
    return("cedar_programs predates mapping-provenance tracking")
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
