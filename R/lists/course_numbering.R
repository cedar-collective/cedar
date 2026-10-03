# CEDAR-INSTITUTION: course-number conventions
# Course level is read from the LEADING DIGIT of the course number, whatever its
# length. UNM numbers courses with three digits (HIST 301, NURS 702) and, since
# the statewide renumbering, four (HIST 1110, NMNC 3110, BUSA 3001); both share
# the same leading-digit bands. Adopters with a different numbering scheme
# replace this vector.
#
# A rule keyed on the number's VALUE cannot serve both lengths: the old DESR rule
# sent every number >= 1000 to "lower", so 3000/4000-level 4-digit courses were
# classified lower division (ISSUES.md I5). Fall 2026 alone had 289 such
# sections, when Business, Accounting and Population Health renumbered.
#
# 7xx-9xx are graduate and professional work (DNP, MBA, Law, MD-PhD clinicals).
# ISEP 8xx/9xx are study-abroad exchange placeholders that this rule also calls
# "grad"; their number carries no level.
COURSE_LEVEL_BY_LEADING_DIGIT <- c(
  "0" = "lower", "1" = "lower", "2" = "lower",
  "3" = "upper", "4" = "upper",
  "5" = "grad",  "6" = "grad",  "7" = "grad", "8" = "grad", "9" = "grad"
)
