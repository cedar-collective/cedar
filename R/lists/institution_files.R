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
  # source_names: every other spelling or former code a source uses for the
  # college, `|`-separated ("College of Education|ED" for EH).
  colleges = c("college_code", "college_name", "source_names"),
  # college_code: the unit's home college. Programs reach their college through
  # their unit (ADR-002, "Colleges are mapped, not read").
  units    = c("unit_code", "unit_name", "college_code", "notes"),
  subjects = c("subject_code", "college_code", "unit_code", "notes"),
  # in_college: blank, or the one college where this row applies instead of the
  # code's every-college row. college_code: blank, or this program's college
  # when it differs from its unit's.
  programs = c("program_code", "in_college", "program_name", "unit_code",
               "college_code", "is_pre_major", "leads_to", "basis", "status",
               "evidence", "notes"),
  settings = c("setting", "value")
)

# Settings every institution must declare in settings.csv.
#   mapping_files_url: where people edit these files -- a GitHub "blob" URL for
#   the institution's directory, e.g. https://github.com/<org>/<repo>/blob/main/institution/<id>.
#   The Admin > Mappings page links each row needing a decision to its line.
#   source_files_url: the same repository's root, as a GitHub "blob" URL, for
#   links to platform files that still hold mappings (R/lists/program_code_maps.R
#   until ADR-002 retires it).
CEDAR_REQUIRED_SETTINGS <- c("mapping_files_url", "source_files_url")
# Optional settings.
#   source_values_without_college: `|`-separated source college values that
#   deliberately name no college (UNM's "Non-Degree Status"), so the mapping
#   audit does not list them as unknown.
CEDAR_OPTIONAL_SETTINGS <- c("source_values_without_college")

# Evidence aid for the mapping assistant (scripts/propose-mappings.R). It says
# what each source-system department means; the transform never reads it, so it
# is not part of read_institution_mappings(). unit_code holds one unit for a
# `department`, several `|`-separated candidates for a `split`, and nothing for
# a `bucket` or `non_degree`.
CEDAR_SOURCE_DEPARTMENT_SPEC <- c("source_name", "unit_code", "kind", "notes")
CEDAR_SOURCE_DEPARTMENT_KINDS <- c("department", "split", "bucket", "non_degree")

# Why a program row names the unit it does. no_unit is a decision that nothing
# owns the program (Non-Degree, Undecided) -- distinct from a code with no row,
# which nobody has looked at yet. unresolved marks a proposal the assistant
# found no evidence for; it can never be confirmed.
CEDAR_PROGRAM_BASES <- c("source_department", "subject_code", "inherited",
                         "name_match", "course_taking", "decided", "override",
                         "no_unit", "unresolved")
# Only confirmed rows assign a unit. A proposed row is a suggestion, shown for
# review, that assigns nothing.
CEDAR_PROGRAM_STATUSES <- c("confirmed", "proposed")

read_institution_file <- function(name, dir = cedar_institution_dir()) {
  spec <- if (name == "source_departments") CEDAR_SOURCE_DEPARTMENT_SPEC
          else CEDAR_MAPPING_FILE_SPECS[[name]]
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
  # One row per line: every change is then a one-line diff, and a row can be
  # linked to by its line number (row i is line i + 1). A quoted field with a
  # line break, or a blank line, breaks both.
  n_lines <- length(readLines(path, warn = FALSE, encoding = "UTF-8"))
  if (n_lines != nrow(df) + 1L) {
    stop("[institution_files.R] ", path, " has ", n_lines, " lines for ", nrow(df),
         " rows. Every row must be exactly one line: remove blank lines and line ",
         "breaks inside fields.")
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

  # Columns that may be blank. Everything else is required on every row.
  may_be_blank <- list(
    colleges = "source_names",
    # A unit with no home college yet is listed by the mapping audit.
    units    = c("college_code", "notes"),
    subjects = "notes",
    # The optional college qualifier and override, a pre-major's target, free
    # text, and a unit that is not yet proposed or is decided to be none
    # (checked below).
    programs = c("in_college", "unit_code", "college_code", "leads_to", "evidence", "notes")
  )
  for (nm in names(CEDAR_MAPPING_FILE_SPECS)) {
    key_cols <- setdiff(CEDAR_MAPPING_FILE_SPECS[[nm]], may_be_blank[[nm]])
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
  bad <- setdiff(files$units$college_code[!blank(files$units$college_code)], files$colleges$college_code)
  if (length(bad)) problems <- c(problems, paste("units.csv: college_code not in colleges.csv:", paste(bad, collapse = ", ")))
  # Every source value must name exactly one college, or translation is a guess.
  values <- .college_source_values(files$colleges)
  d <- unique(values$value[duplicated(values$value)])
  if (length(d)) problems <- c(problems, paste("colleges.csv: names more than one college:", paste(d, collapse = ", ")))

  problems <- c(problems, .validate_program_rows(files))
  d <- dup(files$settings, "setting")
  if (length(d)) problems <- c(problems, paste("settings.csv: duplicate setting", paste(d, collapse = ", ")))
  missing <- setdiff(CEDAR_REQUIRED_SETTINGS, files$settings$setting)
  if (length(missing)) problems <- c(problems, paste("settings.csv: missing setting", paste(missing, collapse = ", ")))
  unknown <- setdiff(files$settings$setting, c(CEDAR_REQUIRED_SETTINGS, CEDAR_OPTIONAL_SETTINGS))
  if (length(unknown)) problems <- c(problems, paste("settings.csv: unknown setting", paste(unknown, collapse = ", ")))
  for (key in CEDAR_REQUIRED_SETTINGS) {
    url <- files$settings$value[files$settings$setting == key]
    if (length(url) == 1 && !grepl("^https://[^ ]+/blob/[^ ]+$", url)) {
      problems <- c(problems, paste0("settings.csv: ", key, " must be a GitHub blob URL ",
                                     "(https://github.com/<org>/<repo>/blob/<branch>[/<path>]), got ", url))
    }
  }

  if (length(problems)) {
    stop("[institution_files.R] Invalid mapping files:\n  ",
         paste(problems, collapse = "\n  "), call. = FALSE)
  }
  files
}

.validate_program_rows <- function(files) {
  pr <- files$programs
  problems <- character(0)
  add <- function(msg, bad) {
    if (length(bad)) problems <<- c(problems, paste0("programs.csv: ", msg, " ",
                                                     paste(unique(bad), collapse = ", ")))
  }
  blank <- function(x) is.na(x) | !nzchar(x)
  key <- paste(pr$program_code, pr$in_college, sep = " / ")
  add("duplicate program/in_college", key[duplicated(key)])
  add("unknown basis", setdiff(pr$basis, CEDAR_PROGRAM_BASES))
  add("unknown status", setdiff(pr$status, CEDAR_PROGRAM_STATUSES))
  add("is_pre_major must be TRUE or FALSE:", setdiff(pr$is_pre_major, c("TRUE", "FALSE")))
  add("unit_code not in units.csv:", setdiff(pr$unit_code[!blank(pr$unit_code)], files$units$unit_code))
  add("in_college not in colleges.csv:",
      setdiff(pr$in_college[!blank(pr$in_college)], files$colleges$college_code))
  add("college_code not in colleges.csv:",
      setdiff(pr$college_code[!blank(pr$college_code)], files$colleges$college_code))
  add("leads_to is not a program_code:", setdiff(pr$leads_to[!blank(pr$leads_to)], pr$program_code))
  add("leads_to set on a row that is not a pre-major:",
      pr$program_code[!blank(pr$leads_to) & pr$is_pre_major != "TRUE"])
  # A confirmed row either names a unit or records that nothing owns it.
  add("confirmed with no unit_code (use basis no_unit if nothing owns it):",
      pr$program_code[pr$status == "confirmed" & blank(pr$unit_code) & pr$basis != "no_unit"])
  add("basis no_unit with a unit_code:", pr$program_code[pr$basis == "no_unit" & !blank(pr$unit_code)])
  add("basis unresolved must be a proposed row with no unit_code:",
      pr$program_code[pr$basis == "unresolved" & (pr$status != "proposed" | !blank(pr$unit_code))])
  problems
}

#' Check a source_departments.csv against the institution's units
validate_source_departments <- function(sd, units) {
  problems <- character(0)
  d <- sd$source_name[duplicated(sd$source_name)]
  if (length(d)) problems <- c(problems, paste("duplicate source_name", paste(d, collapse = ", ")))
  bad <- setdiff(sd$kind, CEDAR_SOURCE_DEPARTMENT_KINDS)
  if (length(bad)) problems <- c(problems, paste("unknown kind", paste(bad, collapse = ", ")))
  n_units <- lengths(strsplit(sd$unit_code, "|", fixed = TRUE))
  wrong <- sd$source_name[(sd$kind == "department" & n_units != 1) |
                          (sd$kind == "split" & n_units < 2) |
                          (sd$kind %in% c("bucket", "non_degree") & n_units != 0)]
  if (length(wrong)) problems <- c(problems, paste(
    "wrong number of units for kind (department 1, split 2+, bucket/non_degree none):",
    paste(wrong, collapse = ", ")))
  bad <- setdiff(unlist(strsplit(sd$unit_code, "|", fixed = TRUE)), units$unit_code)
  if (length(bad)) problems <- c(problems, paste("unit_code not in units.csv:", paste(bad, collapse = ", ")))
  if (length(problems)) {
    stop("[institution_files.R] Invalid source_departments.csv:\n  ",
         paste(problems, collapse = "\n  "), call. = FALSE)
  }
  sd
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
    # The subject's own college, never the unit's home college: a branch
    # campus's HLED is a different row from the main campus's.
    files$units[c("unit_code", "unit_name")], by = "unit_code", all.x = TRUE, sort = FALSE
  )
  out <- merge(out, files$colleges[c("college_code", "college_name")],
               by = "college_code", all.x = TRUE, sort = FALSE)
  out <- out[order(out$.row), ]
  tibble::tibble(
    college_code = out$college_code,
    college_name = out$college_name,
    dept_code    = out$unit_code,
    dept_name    = out$unit_name,
    subject_code = out$subject_code
  )
}

#' The unit each program row resolves to, under the ADR-002 contract
#'
#' One tier: the row for (program_code, in_college) if one exists, else the
#' row for program_code with a blank in_college. Only confirmed rows assign a unit;
#' a code with no row, a proposed row, or a no_unit row resolves to NA. Never
#' falls back to the code itself -- that self-naming fallback is the failure
#' ADR-002 exists to remove (ISSUES.md I7).
#'
#' @param program_code,college_code Parallel character vectors, one per data
#'   row: the program code and the college the source recorded the row under.
#' @param programs The programs.csv data frame.
#' @return A character vector of unit codes, NA where none is assigned.
resolve_program_units <- function(program_code, college_code, programs) {
  rows <- .confirmed_program_rows(program_code, college_code, programs)
  unname(ifelse(is.na(rows), NA_character_, programs$unit_code[rows]))
}

# Which confirmed programs.csv row each data row resolves through: the row for
# (code, in_college) if there is one, else the code's every-college row. NA
# where no confirmed row with a unit applies.
.confirmed_program_rows <- function(program_code, college_code, programs) {
  if (length(program_code) != length(college_code)) {
    stop("[institution_files.R] program_code and college_code must be the same length")
  }
  idx  <- seq_len(nrow(programs))
  ok   <- programs$status == "confirmed" & nzchar(programs$unit_code)
  spec <- ok & nzchar(programs$in_college)
  gen  <- ok & !nzchar(programs$in_college)
  at_college <- idx[spec][match(paste(program_code, college_code, sep = ":"),
                               paste(programs$program_code[spec], programs$in_college[spec], sep = ":"))]
  dplyr::coalesce(at_college, idx[gen][match(program_code, programs$program_code[gen])])
}

#' The college each program row reports under, under the ADR-002 contract
#'
#' Program -> unit -> college, stated in the files: the program row's own
#' college_code if it sets one, else (for a pre-major) the college of the
#' program it leads to if that program sets one, else its unit's home college
#' from units.csv. A row with no unit has no college. Never reads a college off
#' the data row: the source's college only chooses an in_college row, as it
#' chooses the unit.
#'
#' @inheritParams resolve_program_units
#' @param files The list read_institution_mappings() returns.
#' @return A character vector of college codes, NA where none is assigned.
resolve_program_colleges <- function(program_code, college_code, files) {
  pr   <- files$programs
  rows <- .confirmed_program_rows(program_code, college_code, pr)
  own  <- dplyr::na_if(pr$college_code[rows], "")
  target <- dplyr::na_if(pr$leads_to[rows], "")
  gen  <- !nzchar(pr$in_college)
  target_college <- dplyr::na_if(pr$college_code[gen][match(target, pr$program_code[gen])], "")
  unit_college <- dplyr::na_if(
    files$units$college_code[match(pr$unit_code[rows], files$units$unit_code)], "")
  unname(dplyr::coalesce(own, target_college, unit_college))
}

# Every value a source may use for a college, and the college it names: the
# code, the name, and each of source_names.
.college_source_values <- function(colleges) {
  extra <- strsplit(colleges$source_names, "|", fixed = TRUE)
  data.frame(
    value = c(colleges$college_code, colleges$college_name, unlist(extra)),
    college_code = c(colleges$college_code, colleges$college_code,
                     rep(colleges$college_code, lengths(extra))),
    stringsAsFactors = FALSE)
}

#' Translate source college values (codes or names) to college codes
#'
#' @return College codes; NA for a value no colleges.csv row names. Values
#'   declared in source_values_without_college are NA too -- callers that list
#'   unknown values use college_value_is_known() to tell them apart.
translate_source_college <- function(values, files) {
  v <- .college_source_values(files$colleges)
  unname(v$college_code[match(values, v$value)])
}

#' Is each source college value either a college or deliberately none?
college_value_is_known <- function(values, files) {
  none <- files$settings$value[files$settings$setting == "source_values_without_college"]
  none <- if (length(none)) strsplit(none, "|", fixed = TRUE)[[1]] else character(0)
  !is.na(translate_source_college(values, files)) | values %in% none
}

#' Links to an institution's mapping file, for people editing it
#'
#' @param files The list read_institution_mappings() returns.
#' @param name File name without extension, e.g. "programs".
#' @param line Optional line numbers: each gets a link to that line.
#' @return `edit` (opens the file in GitHub's editor) when `line` is NULL,
#'   otherwise one URL per line, showing the file's source at that line.
mapping_file_url <- function(files, name, line = NULL) {
  base <- files$settings$value[files$settings$setting == "mapping_files_url"]
  file_url <- paste0(base, "/", name, ".csv")
  if (is.null(line)) return(sub("/blob/", "/edit/", file_url, fixed = TRUE))
  # plain=1: GitHub otherwise renders a CSV as a table with no line anchors.
  paste0(file_url, "?plain=1#L", line)
}

#' Link to one program's line in programs.csv
#'
#' The code's every-college row (blank in_college) if it has one, else its
#' first row. NA for a code with no row.
#'
#' @param files The list read_institution_mappings() returns.
#' @param codes Program codes.
program_line_url <- function(files, codes) {
  pr <- files$programs
  # Row i of the file is line i + 1; read_institution_file() guarantees it.
  line <- seq_len(nrow(pr)) + 1L
  general <- !nzchar(pr$in_college)
  at <- dplyr::coalesce(line[general][match(codes, pr$program_code[general])],
                        line[match(codes, pr$program_code)])
  ifelse(is.na(at), NA_character_, mapping_file_url(files, "programs", at))
}

#' Link to a file in the repository, by its path from the root
source_file_url <- function(files, path) {
  paste0(files$settings$value[files$settings$setting == "source_files_url"], "/", path)
}
