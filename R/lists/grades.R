# Credit-earning grades used by credit-hour and course-completion calculations.
# This is also the ordinary-grade portion of CEDAR's default DFW passing set.
passing_grades <- c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "CR")

# Analytics grade constants used by the canonical outcome classifiers.
#
# CEDAR's default is a C-or-better threshold: A+ through C and CR pass;
# every other nonblank, non-audit outcome is DFW/nonpassing. Retake grades use
# the same threshold. P and S are deliberately not in the passing set.
GRADES_PASS <- c(
  passing_grades,
  "RA+", "RA", "RA-", "RB+", "RB", "RB-", "RC+", "RC", "RCR"
)

# Some courses accept C- or D-range work. This is an explicit opt-in policy,
# never the default. It adds only those grades; P/S and other outcomes remain
# DFW/nonpassing.
GRADES_PASS_SUB_C_OPT_IN <- c(
  GRADES_PASS,
  "C-", "D+", "D", "D-", "RC-", "RD+", "RD", "RD-"
)

# Known DFW/nonpassing values. Canonical classifiers also treat any other
# nonblank, non-audit grade as DFW so a new code cannot disappear silently.
GRADES_DFW <- c(
  "C-", "D+", "D", "D-", "F", "W", "I", "NC", "NR", "P", "S",
  "RC-", "RD+", "RD", "RD-", "RF", "RI", "RNC", "RNR", "RP"
)

# AUD is not a final academic outcome. Blank/NA grades are handled separately.
GRADES_EXCLUDED_FROM_OUTCOMES <- c("AUD")

# assign point values to letter grades
grades_to_points <- data.frame(grade=c("A+","A","A-","B+","B","B-","C+","C","C-","D+","D","D-","CR","F","NC","NR","W","Drop","I"),
                               points=c(4.3,4,3.7,3.3,3,2.7,2.3,2,1.7,1.3,1,.7,0,0,0,0,0,0,0))

# AUD (audit) students receive no grade and should not appear in DFW calculations.
# They are neither passing nor failing — exclude them before outcome classification.
# Observed in data: ~127 DG/DW-status students carry "AUD" as their final_grade.
