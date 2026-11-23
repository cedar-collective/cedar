# report-specs.R — the MyReports reports CEDAR ingests, and how each file is read.
#
# One entry per report, keyed by the code used on every command line
# (update-data.sh, parse-data.R -r, mrgather). parse-data.R reads a report's
# file by its entry here. scripts/report-registry.sh repeats the code, the file
# signature, the transform stage and the daily flag for the shell scripts, and
# test-data-update-pipeline.R fails when the two disagree. mrgather keeps the
# codes in its own list (REPORT_HANDLERS in mrgather.js).
#
# Adding a report: docs/developers/data-transformation-myreports.md,
# "Adding a MyReports report".
#
#   label             the report's name in MyReports
#   data_file         the parsed file parse-data.R accumulates (<data_file>.qs)
#   filename_sig      text every download's name carries: how a file is matched
#                     to its report
#   term_col          the column naming the term a row was pulled for. A new
#                     pull of a term replaces that term's rows and no others.
#   stage             the transform-to-cedar.R stage (--tables) that builds the
#                     CEDAR table from data_file
#   daily             TRUE when the scheduled refresh asks for the report
#                     without being told to
#   ID_col            columns identifying a person (a student, an instructor,
#                     a staff username): read as text and md5-hashed before
#                     anything is saved
#   drop_cols         direct identifiers, never saved
#   drop_na_col       a column every real row fills: a row where it is missing
#                     or blank is one of the export's own footer lines
#   header_first_col  the first cell of the header row, for an export whose
#                     column names are not on its first line (a title above)
#   parser            an R file with a parse() for a report that needs its own

report_specs <- list(
  desr = list(
    label = "Department Enrollment Status Report",
    data_file = "DESRs",
    term_col = "TERM",
    parser = "parse-DESR.R",
    filename_sig = "Department_Enrollment_Status",
    stage = "sections",
    daily = TRUE
  ),
  cl = list(
    label = "Class List Guided Adhoc",
    data_file = "class_lists",
    term_col = "Academic Period",
    ID_col = c("Primary Instructor ID", "Student ID"),
    drop_cols = c(
      "Primary Instructor Email", "Primary Instructor Preferred First Name",
      "Primary Instructor NetID", "Student Name", "Student First Name",
      "Student Last Name", "Confidentiality Indicator", "Student Email Address",
      "Student Preferred First Name", "Student NetID", "Street Line 1",
      "Street Line 2", "City", "County", "Zip Code", "Nation", "Phone Number",
      "Visa Type", "Registration User ID"
    ),
    filename_sig = "Class_List_Guided_Adhoc",
    stage = "students",
    daily = TRUE
  ),
  as = list(
    label = "Academic Study Detail Guided Adhoc",
    data_file = "academic_studies",
    term_col = "Academic Period",
    ID_col = "ID",
    drop_na_col = "Academic Year",
    drop_cols = c(
      "Student First Name", "Student Last Name", "Confidentiality Indicator",
      "Email Address", "Preferred First Name", "NetID", "Street Line 1",
      "Street Line 2", "City", "County", "County Code", "Zip Code",
      "State/Province", "Phone Number"
    ),
    filename_sig = "Academic_Study_Detail_Guided",
    stage = "programs",
    daily = TRUE
  ),
  deg = list(
    label = "Graduates and Pending Graduates Guided Adhoc",
    data_file = "degrees",
    term_col = "Academic Period",
    ID_col = "ID",
    drop_cols = c(
      "Student Preferred First Name", "Student First Name", "Student Last Name",
      "Student Middle Initial", "Confidentiality Indicator", "Email Address",
      "NetID", "Street Line 1", "Street Line 2", "City", "State/Province",
      "Zipcode", "Phone Number", "Visa Type", "Visa Type Code"
    ),
    filename_sig = "Graduates_and_Pending_Graduates",
    stage = "degrees",
    daily = TRUE
  ),
  # Not daily: production mrgather does not fetch it, and a requested report
  # with no file from today fails the fetch (ISSUES.md I43).
  aa = list(
    label = "Admissions Applicants Detail Guided Adhoc",
    data_file = "admissions_applicants",
    term_col = "Academic Period",
    ID_col = "ID",
    drop_cols = c(
      "Student First Name", "Student Middle Name", "Student Last Name", "Name",
      "Email Address", "Phone Number", "Street Line 1", "Street Line 2", "City",
      "State Province Code", "Zipcode", "Nation", "Nation of Citizenship",
      "Visa Type", "Registration User ID", "Father School", "Mother School"
    ),
    filename_sig = "S_Admissions_Applicants_Detail",
    stage = "applicants",
    daily = FALSE
  ),
  # A pull of one term lists every hold, ended or not, of the students
  # registered in that term: the term picks the students, not the holds. The
  # export opens with the report's title, and closes with a line saying when
  # it ran. The username that placed a hold is hashed, not dropped: most holds
  # are placed by a handful of batch accounts, and which is which is worth
  # keeping. Not daily until production mrgather fetches it.
  holds = list(
    label = "Student Holds (Active) Guided Adhoc",
    data_file = "student_holds",
    term_col = "Academic Period Code",
    ID_col = c("ID", "Hold User Creator"),
    header_first_col = "ID",
    drop_na_col = "Hold Code",
    drop_cols = c(
      "Student Full Name (LFMI)", "Confidentiality Indicator", "Email Address",
      "Phone Number"
    ),
    filename_sig = "S_Student_Holds",
    stage = "holds",
    daily = FALSE
  )
)


#' The line of a report's CSV that holds its column names
#'
#' An export with a title above its table has its header further down, and
#' fread() reads such a file as having no header at all. This finds the header
#' by its first cell.
#'
#' @param csv_file Path to the CSV xlsx2csv wrote.
#' @param first_col The header row's first cell (`header_first_col`).
#' @param max_lines How many lines to search from the top.
#' @return The 1-based line number of the header row; an error when no line
#'   within `max_lines` opens with `first_col`.
find_report_header_line <- function(csv_file, first_col, max_lines = 50L) {
  lines <- readLines(csv_file, n = max_lines, warn = FALSE)
  first_cells <- gsub('^"|"$', "", sub(",.*$", "", lines))
  header_line <- which(first_cells == first_col)
  if (length(header_line) == 0L) {
    stop("[report-specs.R] No header row found in ", basename(csv_file), ": none of its first ",
         length(lines), " lines opens with \"", first_col, "\".", call. = FALSE)
  }
  header_line[[1]]
}


#' Convert a report's .xlsx to a CSV: the whole sheet, or an error
#'
#' A converter that fails or is killed part-way leaves the lines it had
#' written, and `system2()` reports that as a warning and a `status`
#' attribute, which stops nothing. Until 2026-11-23 parse-data.R asked only
#' that a non-empty file existed, so a conversion cut short was read and
#' stored as a smaller report (ISSUES.md I79). Here a converter that does not
#' exit 0 is an error, and what it had written, which is the export unhashed,
#' is removed.
#'
#' What the converter printed is left out of the error: it can quote a cell.
#'
#' @param xlsx_file The export as downloaded.
#' @param csv_file Where the CSV is written.
#' @param converter Path to xlsx2csv.
#' @return `csv_file`, invisibly; an error when the converter did not exit 0,
#'   or left no file or an empty one.
convert_report_export <- function(xlsx_file, csv_file, converter) {
  # The status is read from the attribute, so the warning that repeats it
  # (and the whole command line) is not needed.
  said <- suppressWarnings(system2(converter, args = shQuote(c(xlsx_file, csv_file)),
                                   stdout = TRUE, stderr = TRUE))
  status <- attr(said, "status")
  if (!is.null(status) && status != 0L) {
    unlink(csv_file)
    stop("[report-specs.R] ", basename(converter), " ended with status ", status,
         " while converting ", basename(xlsx_file), ". What it had written was removed ",
         "and nothing was stored. Run it by hand on that file to see what it says.",
         call. = FALSE)
  }
  if (!file.exists(csv_file)) {
    stop("[report-specs.R] ", basename(converter), " wrote no file for ",
         basename(xlsx_file), ".", call. = FALSE)
  }
  if (file.size(csv_file) == 0) {
    unlink(csv_file)
    stop("[report-specs.R] ", basename(converter), " wrote an empty file for ",
         basename(xlsx_file), ".", call. = FALSE)
  }
  invisible(csv_file)
}


#' Read a converted export: every row as written, or an error
#'
#' `fread()` warns and carries on when a line does not fit the table. It
#' returns only the rows above a line with too many cells ("Stopped early on
#' line N"), drops a last line cut off inside a cell ("Discarded single-line
#' footer"), and keeps a last line cut off after one as a row with its cells
#' in the wrong columns ("Found and resolved improper quoting"). Each result
#' looks like a report and is not the one MyReports sent (ISSUES.md I79). Any
#' warning from the read is an error here: no export CEDAR parses raises one
#' when it is whole.
#'
#' A warning quotes the line it is about, between `<<` and `>>`: a person's
#' row as MyReports wrote it, name and unhashed ID included. The error repeats
#' the warning only up to that mark, so the row never reaches a log.
#'
#' @param csv_file Path to the CSV xlsx2csv wrote.
#' @param id_cols Columns read as text (`ID_col`): a numeric read loses an
#'   ID's leading zeros.
#' @param skip Lines above the header row.
#' @return The export as a data.table; an error when the read raised a
#'   warning.
read_report_export <- function(csv_file, id_cols = NULL, skip = 0L) {
  col_classes <- if (length(id_cols) > 0) list(character = id_cols) else NULL
  warned <- character(0)
  export <- withCallingHandlers(
    data.table::fread(csv_file, colClasses = col_classes, skip = skip),
    warning = function(w) {
      warned <<- c(warned, trimws(sub("(?s)<<.*$", "", conditionMessage(w), perl = TRUE)))
      invokeRestart("muffleWarning")
    }
  )
  if (length(warned) > 0) {
    stop("[report-specs.R] ", basename(csv_file), " was not read as written, so nothing ",
         "was stored. The reader returned ", nrow(export), " row(s) and said: ",
         paste(unique(warned), collapse = " | "), call. = FALSE)
  }
  export
}


#' Drop the lines of an export that are not rows of the report
#'
#' A MyReports export can end with blank lines and a line saying when it ran.
#' Every real row fills `column`; a row where it is missing or blank is one of
#' those lines.
#'
#' @param data The report as read.
#' @param column A column every real row fills (`drop_na_col`).
#' @return `data` without the rows whose `column` is NA or blank; an error
#'   when `column` is not in `data`.
drop_report_noise_rows <- function(data, column) {
  if (!column %in% names(data)) {
    stop("[report-specs.R] drop_na_col \"", column, "\" is not a column of the report.", call. = FALSE)
  }
  values <- data[[column]]
  data[!is.na(values) & trimws(as.character(values)) != "", , drop = FALSE]
}
