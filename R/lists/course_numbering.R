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
