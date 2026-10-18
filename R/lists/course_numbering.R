# CEDAR-PLATFORM: course level by leading digit, from institution/<id>/course_levels.csv
# Course level is read from the LEADING DIGIT of the course number, whatever its
# length; the digit-to-level bands are the institution's, in course_levels.csv
# (UNM numbers courses with three digits, HIST 301, and since the statewide
# renumbering four, HIST 1110; both share the same bands).
#
# A rule keyed on the number's VALUE cannot serve both lengths: the old DESR rule
# sent every number >= 1000 to "lower", so 3000/4000-level 4-digit courses were
# classified lower division (ISSUES.md I5). Fall 2026 alone had 289 such
# sections, when Business, Accounting and Population Health renumbered. That is
# why the file is keyed on one digit and must name all ten.
.cedar_course_levels <- validate_course_levels(read_institution_file("course_levels"))

COURSE_LEVEL_BY_LEADING_DIGIT <- stats::setNames(.cedar_course_levels$level,
                                                 .cedar_course_levels$leading_digit)

#' Course level from a course code
#'
#' The one rule for course level, used by cedar_sections, cedar_students and the
#' Degree Explorer catalog validators: the leading digit of the course number,
#' looked up in COURSE_LEVEL_BY_LEADING_DIGIT. Works for 3- and 4-digit numbers
#' and lab suffixes alike ("HIST 301", "NMNC 3110", "PHYS 151L"). It lives here,
#' beside its lookup, because lists load before trunk and the catalog validators
#' run at load time.
#'
#' @param subject_course Character vector like "BUSA 3001".
#' @return Character vector of "lower", "upper", "grad", or NA when the code has
#'   no numeric course number.
course_level_from_number <- function(subject_course) {
  number <- sub("^.*\\s", "", as.character(subject_course))
  lead <- ifelse(grepl("^[0-9]", number), substr(number, 1, 1), NA_character_)
  unname(COURSE_LEVEL_BY_LEADING_DIGIT[lead])
}
