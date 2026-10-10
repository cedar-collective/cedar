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
#'   ("unmapped", "review", or "expected"), consequence, needs (what someone
#'   must supply, in words), file (the mapping file that takes it, without
#'   extension), line (the row to edit there, NA where the fix is a new row).
#'   Attribute `checked`: the kinds checked.
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
  # Banner's own college value, the audit's evidence. From ADR-002 Stage 3b the
  # tables report the mapped college and keep Banner's beside it; a table built
  # before then carries Banner's value in the reported column itself.
  banner_col <- function(df, from_3b, before_3b, what) {
    if (from_3b %in% names(df)) return(df[[from_3b]])
    if (before_3b %in% names(df)) return(df[[before_3b]])
    stop("[mapping-audit.R] ", what, " lacks ", from_3b, " and ", before_3b)
  }
  org_id_or <- function(code, otherwise) dplyr::if_else(
    grepl("^[0-9]+$", code),
    "a Banner organisation ID in the major code column, not a program", otherwise)

  # Course subjects with no subjects.csv row at all.
  course_rows <- if (!is.null(students)) {
    need(students, c("subject_code", "term"), "cedar_students")
    tibble::tibble(subject = students$subject_code,
                   college = banner_col(students, "source_college", "college", "cedar_students"),
                   term = students$term)
  } else if (!is.null(sections)) {
    need(sections, c("subject", "term"), "cedar_sections")
    tibble::tibble(subject = sections$subject,
                   college = banner_col(sections, "source_college", "college", "cedar_sections"),
                   term = sections$term)
  }
  if (!is.null(course_rows)) {
    checked <- c(checked, "subject")
    confirmed_subjects <- files$subjects$subject_code[files$subjects$status == "confirmed"]
    out$subject <- course_rows %>%
      dplyr::filter(!is.na(subject), nzchar(subject),
                    !subject %in% confirmed_subjects) %>%
      span(subject) %>%
      dplyr::left_join(course_rows %>% dplyr::distinct(subject, college) %>%
                         dplyr::group_by(subject) %>%
                         dplyr::summarize(context = paste("college", paste(sort(unique(college)), collapse = ", ")),
                                          .groups = "drop"), by = "subject") %>%
      dplyr::mutate(line = mapping_file_line(files, "subjects", subject),
                    suggested = files$subjects$unit_code[line - 1L]) %>%
      dplyr::transmute(kind = "subject", value = subject,
                       needs = dplyr::case_when(
                         is.na(line) ~ "A subjects.csv row: department and college",
                         nzchar(suggested) ~ paste0("Confirm the suggested department, ", suggested, ", or replace it"),
                         TRUE ~ "A department: nothing settled it"),
                       context = dplyr::if_else(is.na(line), context, paste0(context, "; proposed in subjects.csv")),
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "Its courses have no unit: today CEDAR names a department after the subject",
                       file = "subjects", line)
  }

  # Section colleges no colleges.csv row names.
  if (!is.null(sections)) {
    need(sections, "term", "cedar_sections")
    checked <- c(checked, "section_college")
    out$section_college <- tibble::tibble(
      college = banner_col(sections, "source_college", "college", "cedar_sections"),
      term = sections$term) %>%
      dplyr::filter(!is.na(college), nzchar(college),
                    !college_value_is_known(college, files)) %>%
      span(college) %>%
      dplyr::transmute(kind = "section_college", value = college, context = "DESR college",
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "Its sections match no college, and no subjects.csv row keyed on it",
                       file = "colleges", line = NA_integer_)
  }

  if (!is.null(programs)) {
    need(programs, c("program_type", "major_code", "is_pre_major", "term"), "cedar_programs")
    programs <- programs %>% dplyr::mutate(
      .banner_college      = banner_col(programs, "source_college", "student_college", "cedar_programs"),
      .banner_college_code = banner_col(programs, "source_college_code", "college_code", "cedar_programs"))
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
        file = "programs", line = NA_integer_)

    # College names a source used that no colleges.csv row names.
    out$source_college <- programs %>%
      dplyr::filter(!is.na(.banner_college), nzchar(.banner_college),
                    !college_value_is_known(.banner_college, files)) %>%
      span(.banner_college) %>%
      dplyr::transmute(kind = "source_college", value = .banner_college,
                       context = "Translated College (academic studies)",
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "The audit cannot compare these rows' mapped college with Banner's",
                       file = "colleges", line = NA_integer_)

    # Mapped college (program -> unit -> college) against Banner's Translated
    # College. Each difference is a decision: either the mapping is wrong, or it
    # deliberately differs -- as a pre-major reporting under the college it
    # leads to does, by decision, where Banner keeps some in an advising college.
    majors <- declared %>% dplyr::filter(program_type == "Major") %>%
      dplyr::mutate(
        mapped = resolve_program_colleges(major_code, dplyr::coalesce(.banner_college_code, ""), files),
        banner = translate_source_college(.banner_college, files)) %>%
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
        file = "programs", line = mapping_file_line(files, "programs", major_code))
  }

  if (!is.null(degrees)) {
    need(degrees, c("major_code", "term"), "cedar_degrees")
    degrees <- degrees %>% dplyr::mutate(
      .banner_college = banner_col(degrees, "source_college", "college", "cedar_degrees"))
    checked <- c(checked, "degree_program_code", "degree_college")
    out$degree_program_code <- degrees %>%
      dplyr::filter(!is.na(major_code), !major_code %in% files$programs$program_code) %>%
      span(major_code) %>%
      dplyr::transmute(kind = "program_code", value = major_code,
                       context = org_id_or(major_code, "degree record"),
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "Its graduates have no unit: today CEDAR names a department after the code",
                       file = "programs", line = NA_integer_)
    out$degree_college <- degrees %>%
      dplyr::filter(!is.na(.banner_college), nzchar(.banner_college),
                    !college_value_is_known(.banner_college, files)) %>%
      span(.banner_college) %>%
      dplyr::transmute(kind = "source_college", value = .banner_college, context = "degree record",
                       rows, first_term, last_term, status = "unmapped",
                       consequence = "These degrees' college cannot be compared or translated",
                       file = "colleges", line = NA_integer_)
  }

  # Units with no home college: their programs and courses reach no college.
  checked <- c(checked, "unit_college")
  no_college <- files$units$unit_code[!nzchar(files$units$college_code)]
  out$unit_college <- tibble::tibble(
    kind = "unit_college", value = no_college, context = "units.csv",
    rows = NA_integer_, first_term = NA_integer_, last_term = NA_integer_,
    status = "unmapped", consequence = "Its programs report under no college",
    file = "units", line = mapping_file_line(files, "units", no_college))

  audit <- dplyr::bind_rows(out)
  if (nrow(audit) == 0) {
    audit <- tibble::tibble(kind = character(), value = character(), context = character(),
                            rows = integer(), first_term = integer(), last_term = integer(),
                            status = character(), consequence = character(), needs = character(),
                            file = character(), line = integer())
  }
  # Only the subject check words its own needs; with no course table loaded,
  # no row carries the column yet.
  if (!"needs" %in% names(audit)) audit$needs <- NA_character_
  audit <- audit %>%
    dplyr::mutate(needs = dplyr::coalesce(needs, .audit_needs(kind, status, line, context))) %>%
    dplyr::arrange(match(status, c("unmapped", "review", "expected")), dplyr::desc(rows))
  # No names on any column: a named vector reaches the browser as a JSON object,
  # not an array, and a table built from it renders nothing, silently.
  audit <- dplyr::mutate(audit, dplyr::across(dplyr::everything(), unname))
  attr(audit, "checked") <- checked
  audit
}

# What a person must supply for each audit row, in words.
.audit_needs <- function(kind, status, line, context) {
  dplyr::case_when(
    status == "expected" ~ "Nothing: an expected difference",
    kind %in% c("section_college", "source_college") ~
      "A college for it: add to source_names, or to source_values_without_college",
    kind == "program_code" & grepl("organisation ID", context) ~
      "Nothing to map: a source data error to report",
    kind == "program_code" ~ "A programs.csv row: run propose-mappings.R --write",
    kind == "college_disagreement" ~ "A decision: confirm, or set the program's college_code",
    kind == "unit_college" ~ "A home college for the unit",
    TRUE ~ NA_character_)
}

#' One line for a log: what the audit found
summarize_mapping_audit <- function(audit) {
  n <- function(s) sum(audit$status == s)
  sprintf("Mapping audit: %d unmapped value(s), %d mapped college(s) to review, %d expected difference(s). Checked: %s.",
          n("unmapped"), n("review"), n("expected"),
          paste(attr(audit, "checked"), collapse = ", "))
}
