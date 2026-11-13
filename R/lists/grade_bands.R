# CEDAR-PLATFORM: letter bands for reading a later outcome by an earlier grade
#
# Course Dynamics > Later Course reads what students did in a later course by
# the grade they earned in the earlier one. The three lists are the passing
# letters; every other band is an outcome category of cedar_attempts, so a
# band never contradicts the pass line: add_attempt_grade_band()
# (R/branches/attempts.R) assigns "C- to F", "Withdrew" and the two "Other"
# bands from the stored category. GRADE_BAND_LEVELS is the display order.
#
# Its own file, not grades.R: grades.R is projection model source
# (enrollment_projection_model_source_files()), where any edit rebuilds both
# projection bundles at deploy, and no projection reads a band.
GRADE_LETTER_BANDS <- list(
  "A" = c("A+", "A", "A-", "RA+", "RA", "RA-"),
  "B" = c("B+", "B", "B-", "RB+", "RB", "RB-"),
  "C" = c("C+", "C", "RC+", "RC")
)
GRADE_BAND_LEVELS <- c(names(GRADE_LETTER_BANDS), "C- to F", "Withdrew",
                       "Other passing", "Other nonpassing", "Not graded")
