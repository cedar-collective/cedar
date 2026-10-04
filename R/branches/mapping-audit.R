# mapping-audit.R — every value in the data that the mapping files do not cover
#
# ADR-002's contract: a code with no row in the mapping files gets no unit, is
# never given one named after itself, never blocks a refresh -- and is listed,
# the day it arrives, so that someone decides it. This is that list. It runs at
# the end of every transform (the refresh log) and on Admin > Mappings (always
# current with both the data and the files), from the same function.
#
# It reads only what the CEDAR tables carry. The source departments the mapping
# assistant reads (source_departments.csv) are its own business: the transform
# never uses them, and the assistant reports any it does not know.

#' Values in the data with no mapping, and mapped colleges Banner disagrees with
#'
#' @param files The list read_institution_mappings() returns.
#' @param sections,students,programs,degrees CEDAR tables; any may be NULL, and
#'   the kinds that need it are then not checked (and say so in `checked`).
#' @return Tibble: kind, value, context, rows, first_term, last_term, status
#'   ("unmapped", "review", or "expected"), consequence, fix_file. Attribute
#'   `checked`: the kinds that were checked.
audit_mapping_coverage <- function(files, sections = NULL, students = NULL,
                                   programs = NULL, degrees = NULL) {
  out <- list()
  checked <- character(0)
  need <- function(df, cols, what) {
    missing <- setdiff(cols, names(df))
    if (length(missing)) {
      stop("[mapping-audit.R] ", what, " lacks ", paste(missing, collapse = ", "))
    }
  }
  # A group whose terms are all missing has no first or last term, not Inf.
  edge <- function(x, f) if (all(is.na(x))) NA_integer_ else as.integer(f(x, na.rm = TRUE))
  span <- function(df, ...) df %>%
    dplyr::group_by(...) %>%
    dplyr::summarize(rows = dplyr::n(), first_term = edge(term, min),
                     last_term = edge(term, max), .groups = "drop")
  org_id_or <- function(code, otherwise) dplyr::if_else(
    grepl("^[0-9]+$", code),
    "a Banner organisation ID in the major code column, not a program", otherwise)

  # Course subjects with no subjects.csv row at all.
  course_rows <- if (!is.null(students)) {
    need(students, c("subject_code", "college", "term"), "cedar_students")
    students %>% dplyr::select(subject = subject_code, college, term)
  } else if (!is.null(sections)) {
    need(sections, c("subject", "college", "term"), "cedar_sections")
    sections %>% dplyr::select(subject, college, term)
  }
  if (!is.null(course_rows)) {
    checked <- c(checked, "subject")
    out$subject <- course_rows %>%
      dplyr::filter(!is.na(subject), nzchar(subject),
                    !subject %in% files$subjects$subject_code) %>%
      span(subject) %>%
      dplyr::left_join(course_rows %>% dplyr::distinct(subject, college) %>%
                         dplyr::group_by(subject) %>%
                         dplyr::summarize(context = paste("college", paste(sort(unique(college)), collapse = ", ")),
                                          .groups = "drop"), by = "subject") %>%
      dplyr::transmute(kind = "subject", value = subject, context, rows, first_term, last_term,
                       status = "unmapped",
                       consequence = "Its courses have no unit: today CEDAR names a department after the subject",
                       fix_file = "subjects")
  }

  # Section colleges no colleges.csv row names.
  if (!is.null(sections)) {
    need(sections, c("college", "term"), "cedar_sections")
    checked <- c(checked, "section_college")
    out$section_college <- sections %>%
      dplyr::filter(!is.na(college), nzchar(college),
                    !college_value_is_known(college, files)) %>%
      span(college) %>%
      dplyr::transmute(kind = "section_college", value = college, context = "DESR college",
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "Its sections match no college, and no subjects.csv row keyed on it",
                       fix_file = "colleges")
  }

  if (!is.null(programs)) {
    need(programs, c("program_type", "major_code", "college_code", "student_college",
                     "is_pre_major", "term"), "cedar_programs")
    declared <- programs %>%
      dplyr::filter(!grepl("Concentration", program_type), !is.na(major_code))
    checked <- c(checked, "program_code", "source_college", "college_disagreement")

    # Program codes with no programs.csv row.
    out$program_code <- declared %>%
      dplyr::filter(!major_code %in% files$programs$program_code) %>%
      span(major_code) %>%
      dplyr::transmute(
        kind = "program_code", value = major_code,
        context = org_id_or(major_code, "program record"),
        rows, first_term, last_term, status = "unmapped",
        consequence = "Its students have no unit: today CEDAR names a department after the code",
        fix_file = "programs")

    # College names a source used that no colleges.csv row names.
    out$source_college <- programs %>%
      dplyr::filter(!is.na(student_college), nzchar(student_college),
                    !college_value_is_known(student_college, files)) %>%
      span(student_college) %>%
      dplyr::transmute(kind = "source_college", value = student_college,
                       context = "Translated College (academic studies)",
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "The audit cannot compare these rows' mapped college with Banner's",
                       fix_file = "colleges")

    # Mapped college (program -> unit -> college) against Banner's Translated
    # College. Each difference is a decision: either the mapping is wrong, or it
    # deliberately differs -- as a pre-major reporting under the college it
    # leads to does, by decision, where Banner keeps some in an advising college.
    majors <- declared %>% dplyr::filter(program_type == "Major") %>%
      dplyr::mutate(
        mapped = resolve_program_colleges(major_code, dplyr::coalesce(college_code, ""), files),
        banner = translate_source_college(student_college, files)) %>%
      dplyr::filter(!is.na(mapped), !is.na(banner), mapped != banner)
    out$college_disagreement <- majors %>%
      span(major_code, mapped, banner, is_pre_major) %>%
      dplyr::transmute(
        kind = "college_disagreement", value = major_code,
        context = paste0("mapped ", mapped, ", Banner Translated College ", banner),
        rows, first_term, last_term,
        status = dplyr::if_else(is_pre_major, "expected", "review"),
        consequence = dplyr::if_else(
          is_pre_major,
          "A pre-major reports under the college it leads to (decided); Banner keeps some in an advising college",
          "Reports under a different college from the one Banner records"),
        fix_file = "programs")
  }

  if (!is.null(degrees)) {
    need(degrees, c("major_code", "college", "term"), "cedar_degrees")
    checked <- c(checked, "degree_program_code", "degree_college")
    out$degree_program_code <- degrees %>%
      dplyr::filter(!is.na(major_code), !major_code %in% files$programs$program_code) %>%
      span(major_code) %>%
      dplyr::transmute(kind = "program_code", value = major_code,
                       context = org_id_or(major_code, "degree record"),
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "Its graduates have no unit: today CEDAR names a department after the code",
                       fix_file = "programs")
    out$degree_college <- degrees %>%
      dplyr::filter(!is.na(college), nzchar(college), !college_value_is_known(college, files)) %>%
      span(college) %>%
      dplyr::transmute(kind = "source_college", value = college, context = "degree record",
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "These degrees' college cannot be compared or translated",
                       fix_file = "colleges")
  }

  # Units with no home college: their programs and courses reach no college.
  checked <- c(checked, "unit_college")
  no_college <- files$units$unit_code[!nzchar(files$units$college_code)]
  out$unit_college <- tibble::tibble(
    kind = "unit_college", value = no_college, context = "units.csv",
    rows = NA_integer_, first_term = NA_integer_, last_term = NA_integer_,
    status = "unmapped", consequence = "Its programs report under no college",
    fix_file = "units")

  audit <- dplyr::bind_rows(out)
  if (nrow(audit) == 0) {
    audit <- tibble::tibble(kind = character(), value = character(), context = character(),
                            rows = integer(), first_term = integer(), last_term = integer(),
                            status = character(), consequence = character(),
                            fix_file = character())
  }
  audit <- audit %>%
    dplyr::arrange(match(status, c("unmapped", "review", "expected")), dplyr::desc(rows))
  attr(audit, "checked") <- checked
  audit
}

#' One line for a log: what the audit found
summarize_mapping_audit <- function(audit) {
  n <- function(s) sum(audit$status == s)
  sprintf("Mapping audit: %d unmapped value(s), %d mapped college(s) to review, %d expected difference(s). Checked: %s.",
          n("unmapped"), n("review"), n("expected"),
          paste(attr(audit, "checked"), collapse = ", "))
}
