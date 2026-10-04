# CEDAR-PLATFORM: reads and validates an institution's mapping files
# institution_files.R
#
# An institution describes its own units, subjects and colleges in plain CSV
# files under institution/<id>/, so adopting CEDAR means editing reviewed text
# files rather than code. See docs/developers/adr-002-explicit-mapping-files.md.
#
# This file holds the mechanism only. It knows the file names and their
# columns; it contains no institution's codes. Sourced before any list that
# reads institution files, because R/lists loads before R/trunk.
#
# Every problem fails loudly with every problem listed at once: a malformed
# mapping file silently assigns students to the wrong unit, which is the
# failure this design exists to prevent.

# Which institution's files to load. An environment variable rather than a
# config.R setting because config.R is not committed and CI, the demo stack and
# the transform run without one. UNM is the documented default.
cedar_institution_id <- function() {
  id <- Sys.getenv("CEDAR_INSTITUTION", unset = "unm")
  if (!grepl("^[a-z0-9_-]+$", id)) {
    stop("[institution_files.R] CEDAR_INSTITUTION must be a lowercase directory ",
         "name under institution/, got: '", id, "'")
  }
  id
}

# The repository root. Callers set one of two names: cedar_base_dir (the app,
# tests, cedar-repl) or cedar_root (the transform when run as a script). They
# are found through the calling frames because these lists are sourced from
# inside load_funcs() and transform_to_cedar().
.cedar_mapping_base <- function() {
  for (nm in c("cedar_base_dir", "cedar_root")) {
    v <- dynGet(nm, ifnotfound = NULL)
    if (!is.null(v)) return(v)
  }
  getwd()
}

cedar_institution_dir <- function(base_dir = .cedar_mapping_base(),
                                  id = cedar_institution_id()) {
  dir <- file.path(base_dir, "institution", id)
  if (!dir.exists(dir)) {
    stop("[institution_files.R] No mapping files for institution '", id,
         "' at ", dir, ". Set CEDAR_INSTITUTION or create the directory.")
  }
  dir
}

# The files and the columns each must have, in order.
CEDAR_MAPPING_FILE_SPECS <- list(
  colleges = c("college_code", "college_name"),
  units    = c("unit_code", "unit_name"),
  subjects = c("subject_code", "college_code", "unit_code", "notes")
)

read_institution_file <- function(name, dir = cedar_institution_dir()) {
  spec <- CEDAR_MAPPING_FILE_SPECS[[name]]
  if (is.null(spec)) stop("[institution_files.R] Unknown mapping file: ", name)
  path <- file.path(dir, paste0(name, ".csv"))
  if (!file.exists(path)) stop("[institution_files.R] Missing mapping file: ", path)
  df <- utils::read.csv(path, colClasses = "character", na.strings = character(0),
                        check.names = FALSE, strip.white = TRUE,
                        encoding = "UTF-8")
  if (!identical(names(df), spec)) {
    stop("[institution_files.R] ", path, " must have columns ",
         paste(spec, collapse = ", "), "; found ", paste(names(df), collapse = ", "))
  }
  df
}

#' Check an institution's mapping files against each other
#'
#' @return The files as a named list of data frames, if valid. Stops listing
#'   every problem otherwise.
validate_mapping_files <- function(files) {
  problems <- character(0)
  blank <- function(x) is.na(x) | !nzchar(x)
  dup <- function(df, cols) {
    key <- do.call(paste, c(df[cols], sep = " / "))
    unique(key[duplicated(key)])
  }

  for (nm in names(CEDAR_MAPPING_FILE_SPECS)) {
    key_cols <- setdiff(CEDAR_MAPPING_FILE_SPECS[[nm]], "notes")
    for (col in key_cols) {
      n_blank <- sum(blank(files[[nm]][[col]]))
      if (n_blank > 0) problems <- c(problems, sprintf("%s.csv: %d blank %s", nm, n_blank, col))
    }
  }
  d <- dup(files$colleges, "college_code")
  if (length(d)) problems <- c(problems, paste("colleges.csv: duplicate college_code", paste(d, collapse = ", ")))
  d <- dup(files$units, "unit_code")
  if (length(d)) problems <- c(problems, paste("units.csv: duplicate unit_code", paste(d, collapse = ", ")))
  d <- dup(files$subjects, c("subject_code", "college_code"))
  if (length(d)) problems <- c(problems, paste("subjects.csv: duplicate subject/college", paste(d, collapse = ", ")))

  bad <- setdiff(files$subjects$unit_code, files$units$unit_code)
  if (length(bad)) problems <- c(problems, paste("subjects.csv: unit_code not in units.csv:", paste(bad, collapse = ", ")))
  bad <- setdiff(files$subjects$college_code, files$colleges$college_code)
  if (length(bad)) problems <- c(problems, paste("subjects.csv: college_code not in colleges.csv:", paste(bad, collapse = ", ")))

  if (length(problems)) {
    stop("[institution_files.R] Invalid mapping files:\n  ",
         paste(problems, collapse = "\n  "), call. = FALSE)
  }
  files
}

read_institution_mappings <- function(dir = cedar_institution_dir()) {
  files <- lapply(stats::setNames(nm = names(CEDAR_MAPPING_FILE_SPECS)),
                  read_institution_file, dir = dir)
  validate_mapping_files(files)
}

#' The subject → unit → college table every CEDAR lookup is derived from
#'
#' One row per subjects.csv row, in file order: lookups built from it take the
#' first match, so the order is part of the contract. A subject can appear
#' under two colleges with different units -- branch campuses reuse codes such
#' as HLED, PH and SUST -- which is why subjects are keyed by subject AND college.
#' Column names are the ones the rest of CEDAR has always read.
build_subj_dept_map <- function(files) {
  out <- merge(
    data.frame(.row = seq_len(nrow(files$subjects)), files$subjects,
               check.names = FALSE),
    files$units, by = "unit_code", all.x = TRUE, sort = FALSE
  )
  out <- merge(out, files$colleges, by = "college_code", all.x = TRUE, sort = FALSE)
  out <- out[order(out$.row), ]
  tibble::tibble(
    college_code = out$college_code,
    college_name = out$college_name,
    dept_code    = out$unit_code,
    dept_name    = out$unit_name,
    subject_code = out$subject_code
  )
}
