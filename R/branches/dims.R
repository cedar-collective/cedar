# dims.R — the dimension tables, and the one function that attaches a unit
#
# ADR-001 step 3. The institution's mapping files (institution/<id>/, read and
# validated by R/lists/institution_files.R) are CEDAR's dimension tables:
# colleges, units, subjects, programs, and the settings beside them. They are
# read at every start and never written into a saved table: edit a CSV, open a
# pull request, restart. build_cedar_dims() wraps the validated files as one
# classed object, `dims`, built once by each entry point (global.R, the
# cache-warming scripts, cedar-repl.R) and handed to the code that needs a
# dimension by name.
#
# attach_unit() is the only code that resolves a unit for a row. It wraps the
# two rules that already live in institution_files.R -- resolve_course_units()
# for the subject hierarchy; resolve_program_units() and
# resolve_program_colleges() for the program hierarchy -- and writes the result
# under the names every reader has always read: department / college /
# college_basis on a section or class-list row, dept_code / college_code /
# college_basis on a declaration or degree. A row the files do not cover gets
# NA and a basis, never a unit named after itself (the rule EC-14 guards).
# test-architecture.R fails on a unit resolved anywhere else.
#
# attach_default_units() is what a loader calls: it drops any stamped unit
# column it finds on a fact table and attaches the default hierarchy, so the
# in-memory tables look the same whatever the transform wrote. The transform
# writes keys only (the subject, the program code, the source's college) since
# the step's second PR; a file stamped by an older transform loads the same
# way, its copy dropped first. The ADR records the measurement that the two
# agree on every row.
#
# A reader that wants another hierarchy -- a course under its instructor's
# unit, a Gen Ed course under its awarding college -- calls attach_unit() with
# its own `cols`, never into the default columns: a column's name is what
# tells a reader which rule produced it.

# The mapping tables a dims object carries, in the order the files are read.
CEDAR_DIM_TABLES <- names(CEDAR_MAPPING_FILE_SPECS)

#' Build the dimension object from the validated mapping files
#'
#' @param files The list read_institution_mappings() returns; by default the
#'   one the lists layer read at load (`cedar_institution_files`).
#' @return The same tables, classed `cedar_dims`, so a function that takes
#'   `dims` can tell it was built here and validated.
build_cedar_dims <- function(files = cedar_institution_files) {
  if (!is.list(files)) {
    stop("[dims.R] build_cedar_dims: files must be the list read_institution_mappings() returns")
  }
  missing <- setdiff(CEDAR_DIM_TABLES, names(files))
  if (length(missing)) {
    stop("[dims.R] build_cedar_dims: missing mapping table(s): ", paste(missing, collapse = ", "))
  }
  dims <- structure(files[CEDAR_DIM_TABLES], class = c("cedar_dims", "list"))
  validate_cedar_dims(dims)
}

#' Refuse anything that is not a dims object with every table and column
validate_cedar_dims <- function(dims) {
  if (!inherits(dims, "cedar_dims")) {
    stop("[dims.R] dims must be built by build_cedar_dims()")
  }
  for (nm in CEDAR_DIM_TABLES) {
    tbl <- dims[[nm]]
    if (!is.data.frame(tbl)) stop("[dims.R] dims$", nm, " is not a table")
    missing <- setdiff(CEDAR_MAPPING_FILE_SPECS[[nm]], names(tbl))
    if (length(missing)) {
      stop("[dims.R] dims$", nm, " lacks column(s) ", paste(missing, collapse = ", "))
    }
  }
  invisible(dims)
}

# The two default hierarchies: which row columns each rule reads (`keys`) and
# the columns it writes (`cols`). `college` is the source's college for the
# row, which chooses a college-specific mapping row and, where the files do
# not decide, is reported translated and labelled "banner". The program rule
# reads a second source column, `banner`, preferred for that label (academic
# studies' Translated College, with its Actual College as the key).
CEDAR_UNIT_HIERARCHIES <- list(
  subject = list(
    keys = c(subject = "subject_code", college = "source_college", level = "level"),
    cols = c(unit = "department", college = "college", basis = "college_basis")),
  program = list(
    keys = c(program = "major_code", college = "source_college_code", banner = "source_college"),
    cols = c(unit = "dept_code", college = "college_code", basis = "college_basis"))
)

#' Attach a unit and college to rows, under one named hierarchy
#'
#' @param rows A fact table: sections or class-list rows for the subject
#'   hierarchy; declarations or degrees for the program hierarchy.
#' @param dims The object build_cedar_dims() returns.
#' @param hierarchy `"subject"` (the subject's unit, from subjects.csv, keyed
#'   on subject, the source's section college and the course level) or
#'   `"program"` (the program's unit, from programs.csv, keyed on the code and
#'   the source's college).
#' @param keys Named overrides for the columns the rule reads, e.g.
#'   `c(subject = "subject")` for sections. Names as in CEDAR_UNIT_HIERARCHIES.
#' @param cols Named overrides for the columns written: `unit`, `college`,
#'   `basis`, and optionally `decided` (whether the files decide the row) and
#'   `banner` (the source's college, translated), which are written only when
#'   named. Another hierarchy writes its own names, never the defaults.
#' @return `rows` with the named columns added. Refuses rows missing a key
#'   column or already carrying an output column: drop them first, as
#'   attach_default_units() does, rather than overwrite silently.
attach_unit <- function(rows, dims, hierarchy = c("subject", "program"),
                        keys = NULL, cols = NULL) {
  hierarchy <- match.arg(hierarchy)
  validate_cedar_dims(dims)
  if (!is.data.frame(rows)) stop("[dims.R] attach_unit: rows must be a data frame")
  spec <- CEDAR_UNIT_HIERARCHIES[[hierarchy]]
  keys <- .merge_named(spec$keys, keys, "keys", allowed = names(spec$keys))
  cols <- .merge_named(spec$cols, cols, "cols",
                       allowed = c("unit", "college", "basis", "decided", "banner"))
  missing <- setdiff(unname(keys), colnames(rows))
  if (length(missing)) {
    stop("[dims.R] attach_unit(", hierarchy, "): rows lack key column(s) ",
         paste(missing, collapse = ", "))
  }
  present <- intersect(unname(cols), colnames(rows))
  if (length(present)) {
    stop("[dims.R] attach_unit(", hierarchy, "): rows already carry ",
         paste(present, collapse = ", "), "; drop the stamped columns first")
  }
  resolved <- switch(hierarchy,
    subject = .resolve_subject_hierarchy(rows, dims, keys),
    program = .resolve_program_hierarchy(rows, dims, keys))
  for (what in names(cols)) rows[[cols[[what]]]] <- resolved[[what]]
  rows
}

.merge_named <- function(defaults, override, what, allowed) {
  if (is.null(override)) return(defaults)
  if (!is.character(override) || is.null(names(override)) || any(!nzchar(names(override)))) {
    stop("[dims.R] attach_unit: ", what, " must be a named character vector")
  }
  unknown <- setdiff(names(override), allowed)
  if (length(unknown)) {
    stop("[dims.R] attach_unit: unknown ", what, " ", paste(unknown, collapse = ", "),
         "; allowed: ", paste(allowed, collapse = ", "))
  }
  defaults[names(override)] <- override
  defaults
}

# The subject rule: the most specific confirmed subjects.csv row for the
# subject, the source's college and the level. A course the files decide
# reports the row's college (its unit's home college unless the row credits
# another); one they do not reports the source's college translated through
# colleges.csv, labelled "banner".
.resolve_subject_hierarchy <- function(rows, dims, keys) {
  source_college <- rows[[keys[["college"]]]]
  units <- resolve_course_units(rows[[keys[["subject"]]]], source_college,
                                rows[[keys[["level"]]]], dims)
  banner <- translate_source_college(source_college, dims)
  undecided <- is.na(units$unit_code)
  list(
    unit = units$unit_code,
    college = dplyr::if_else(undecided, banner, units$college_code),
    basis = dplyr::case_when(
      !undecided & !is.na(units$college_code) ~ "mapped",
      undecided & !is.na(banner)              ~ "banner",
      TRUE                                    ~ NA_character_),
    decided = !undecided,
    banner = banner)
}

# The program rule: the confirmed programs.csv row for (code, source college)
# if there is one, else the code's every-college row. A decided code reports
# the college the files give it (its own, its target's, else its unit's; a
# no_unit code may still name one); an undecided code reports the source's
# college translated, labelled "banner". The source's college is read as a
# code: a value already translated passes through unchanged.
.resolve_program_hierarchy <- function(rows, dims, keys) {
  code <- rows[[keys[["program"]]]]
  source_college <- rows[[keys[["college"]]]]
  college_key <- dplyr::coalesce(translate_source_college(source_college, dims), "")
  unit <- resolve_program_units(code, college_key, dims$programs)
  decided <- !is.na(.confirmed_program_rows(code, college_key, dims$programs, no_unit = TRUE))
  mapped <- resolve_program_colleges(code, college_key, dims)
  banner <- dplyr::coalesce(translate_source_college(rows[[keys[["banner"]]]], dims),
                            translate_source_college(source_college, dims))
  list(
    unit = unit,
    college = dplyr::if_else(decided, mapped, banner),
    basis = dplyr::case_when(
      decided & !is.na(mapped)  ~ "mapped",
      !decided & !is.na(banner) ~ "banner",
      TRUE                      ~ NA_character_),
    decided = decided,
    banner = banner)
}

#' Attach units and colleges to declarations (cedar_programs)
#'
#' Each row's own program resolves through the program rule into `dept_code`
#' and `program_college`. Then the two rules declarations add (ADR-002 Stage
#' 3b): a concentration takes the unit and college of the student's primary
#' major that term (the first Major row by code); and `college_code`,
#' `college_basis` and `student_college` are the STUDENT's college that term,
#' on every one of their rows -- the primary major's college where the files
#' decide that code, else the source's college for the row, labelled "banner".
attach_program_units <- function(programs, dims) {
  needed <- c("student_id", "term", "program_type", "major_code")
  missing <- setdiff(needed, colnames(programs))
  if (length(missing)) {
    stop("[dims.R] attach_program_units: programs lack ", paste(missing, collapse = ", "))
  }
  rows <- attach_unit(programs, dims, "program",
                      cols = c(unit = "dept_code", college = "program_college", basis = ".basis",
                               decided = ".decided", banner = ".banner")) %>%
    # A row's own program's college is the files' answer only: an undecided
    # code has none here. The Banner fallback applies to the student's
    # college below, never to the program's.
    dplyr::mutate(program_college = dplyr::if_else(.decided, program_college, NA_character_))
  primary <- rows %>%
    dplyr::filter(program_type == "Major") %>%
    dplyr::arrange(student_id, term, major_code) %>%
    dplyr::distinct(student_id, term, .keep_all = TRUE) %>%
    dplyr::select(student_id, term, .primary_unit = dept_code,
                  .primary_college = program_college, .primary_decided = .decided)
  rows %>%
    dplyr::left_join(primary, by = c("student_id", "term")) %>%
    dplyr::mutate(
      .concentration = grepl("Concentration", program_type),
      dept_code = dplyr::if_else(.concentration, .primary_unit, dept_code),
      program_college = dplyr::if_else(.concentration, .primary_college, program_college),
      .primary_decided = dplyr::coalesce(.primary_decided, FALSE),
      college_code = dplyr::if_else(.primary_decided, .primary_college, .banner),
      college_basis = dplyr::case_when(
        .primary_decided & !is.na(.primary_college) ~ "mapped",
        !.primary_decided & !is.na(.banner)         ~ "banner",
        TRUE                                        ~ NA_character_),
      student_college = college_names(college_code, dims)) %>%
    dplyr::select(-".basis", -".decided", -".banner", -".primary_unit",
                  -".primary_college", -".primary_decided", -".concentration")
}

#' Attach the unit and college to awarded degrees (cedar_degrees)
#'
#' The program rule keyed on the degree's Actual College
#' (`source_student_college`), with its Translated College (`source_college`)
#' preferred for the "banner" label; `college` and `student_college` are the
#' college's name.
attach_degree_units <- function(degrees, dims) {
  attach_unit(degrees, dims, "program",
              keys = c(college = "source_student_college", banner = "source_college")) %>%
    dplyr::mutate(college = college_names(college_code, dims),
                  student_college = college)
}

#' Attach the unit and college to sections (cedar_sections)
#'
#' The subject rule, keyed on the section's `subject`, then the two columns a
#' crosslist group derives from its sections' units: `crosslist_external`,
#' whether the group spans more than one unit, and `crosslist_partners`, the
#' courses in an external group, sorted. Both follow the unit, so they are
#' attached here rather than stored.
attach_section_units <- function(sections, dims) {
  rows <- attach_unit(sections, dims, "subject", keys = c(subject = "subject"))
  needed <- c("term", "campus", "crosslist_group", "subject_course")
  missing <- setdiff(needed, colnames(rows))
  if (length(missing)) {
    stop("[dims.R] attach_section_units: sections lack ", paste(missing, collapse = ", "))
  }
  present <- intersect(c("crosslist_external", "crosslist_partners"), colnames(rows))
  if (length(present)) {
    stop("[dims.R] attach_section_units: sections already carry ",
         paste(present, collapse = ", "), "; drop the stamped columns first")
  }
  scope <- rows %>%
    dplyr::filter(!is.na(crosslist_group)) %>%
    dplyr::group_by(term, campus, crosslist_group) %>%
    dplyr::summarize(
      crosslist_external = dplyr::n_distinct(department) > 1L,
      crosslist_partners = dplyr::if_else(
        dplyr::n_distinct(department) > 1L,
        paste(sort(unique(subject_course)), collapse = " / "), NA_character_),
      .groups = "drop")
  dplyr::left_join(rows, scope, by = c("term", "campus", "crosslist_group"))
}

#' Attach the primary major's unit and college to student-terms
#'
#' The program rule on the keys the student-term table stores: the primary
#' major's code and the source's college for it (academic studies' Actual and
#' Translated College where a programs row described the term, the roster's
#' Student College Code where the class list did), written as
#' `primary_dept_code`, `primary_college_code` and `primary_college_basis`.
attach_student_term_units <- function(student_terms, dims) {
  attach_unit(student_terms, dims, "program",
              keys = c(program = "primary_major_code", college = "primary_source_college_code",
                       banner = "primary_source_college"),
              cols = c(unit = "primary_dept_code", college = "primary_college_code",
                       basis = "primary_college_basis"))
}

# The unit columns each fact table carries once attached, which a loader drops
# before attaching so a stamped file and an unstamped one load the same way.
CEDAR_ATTACHED_UNIT_COLUMNS <- list(
  cedar_sections = c("department", "college", "college_basis", "crosslist_external", "crosslist_partners"),
  cedar_students = c("department", "college", "college_basis"),
  cedar_programs = c("dept_code", "program_college", "college_code", "college_basis", "student_college"),
  cedar_degrees  = c("dept_code", "college_code", "college_basis", "college", "student_college"),
  cedar_student_terms = c("primary_dept_code", "primary_college_code", "primary_college_basis")
)

#' Attach the default unit columns to every fact table a loader holds
#'
#' @param tables A named list of loaded tables; a table that is not
#'   loaded (NULL, or the empty tibble load_cedar_data() returns for a missing
#'   file) is left alone and named in a message.
#' @param dims The object build_cedar_dims() returns.
#' @return `tables` with the five tables carrying their default unit
#'   columns, the table's attributes kept, each attachment timed in a message.
attach_default_units <- function(tables, dims) {
  validate_cedar_dims(dims)
  if (!is.list(tables)) stop("[dims.R] attach_default_units: tables must be a list")
  for (name in names(CEDAR_ATTACHED_UNIT_COLUMNS)) {
    tbl <- tables[[name]]
    if (is.null(tbl) || !is.data.frame(tbl) || ncol(tbl) == 0L) {
      message("[dims.R] ", name, " is not loaded; nothing attached")
      next
    }
    stamped <- intersect(CEDAR_ATTACHED_UNIT_COLUMNS[[name]], colnames(tbl))
    elapsed <- system.time({
      bare <- tbl[setdiff(colnames(tbl), stamped)]
      attached <- switch(name,
        cedar_sections      = attach_section_units(bare, dims),
        cedar_students      = attach_unit(bare, dims, "subject"),
        cedar_programs      = attach_program_units(bare, dims),
        cedar_degrees       = attach_degree_units(bare, dims),
        cedar_student_terms = attach_student_term_units(bare, dims))
      attached <- .carry_attributes(attached, tbl)
    })[["elapsed"]]
    message(sprintf("[dims.R] %s: attached %s in %.2f s%s", name,
                    paste(CEDAR_ATTACHED_UNIT_COLUMNS[[name]], collapse = ", "), elapsed,
                    if (length(stamped)) paste0(" (", length(stamped), " stamped column(s) dropped first)") else ""))
    tables[[name]] <- attached
  }
  tables
}

# Subsetting drops a table's own attributes (the transform's provenance stamp,
# a policy version); carry them across so a loaded table keeps what its file
# said about it.
.carry_attributes <- function(new, old) {
  keep <- setdiff(names(attributes(old)), c("names", "row.names", "class", "dim", "dimnames"))
  for (a in keep) attr(new, a) <- attr(old, a)
  new
}
