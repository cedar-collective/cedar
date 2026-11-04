# CEDAR-PLATFORM: student level codes from institution/<id>/student_levels.csv
#
# The class list carries a student's level as a code (UG, GR) and academic
# studies as a name (Undergraduate, Graduate/GASM); before this file existed
# the two columns had no values in common, and a filter written for one table
# returned nothing on the other (ADR-001 §2). The institution's file says which
# name is which code, once; the student-term table (R/branches/student-terms.R)
# stores the code. This file contains no level code.
.cedar_student_levels <- validate_student_levels(read_institution_file("student_levels"))

# level_code, level_name, source_names as the file has them.
CEDAR_STUDENT_LEVELS <- .cedar_student_levels

# Display labels by code.
CEDAR_STUDENT_LEVEL_LABELS <- stats::setNames(.cedar_student_levels$level_name,
                                              .cedar_student_levels$level_code)

#' Translate student level values (codes, names or source spellings) to codes
#'
#' @param values Character. Level codes, names, or the spellings listed in
#'   `source_names`.
#' @return Character, parallel to `values`: the level code, or NA where the
#'   file does not name the value. Never a guess: an unlisted value is NA and
#'   the caller reports it.
cedar_level_code_from_source <- function(values) {
  v <- .source_value_table(.cedar_student_levels$level_code,
                           .cedar_student_levels$level_name,
                           .cedar_student_levels$source_names)
  unname(v$code[match(values, v$value)])
}
