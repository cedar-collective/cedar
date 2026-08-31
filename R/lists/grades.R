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

# AUD is not a final academic outcome, even under DG/DW late-drop status.
# Blank/NA grades are handled separately: a late drop still supplies a withdrawal.
GRADES_EXCLUDED_FROM_OUTCOMES <- c("AUD")

# Saved cedar_grades must be rebuilt when classification changes. Version 1 is
# the first stamped policy and excludes late-drop AUD (DFW definition 3.0.0).
# This is an artifact compatibility check, not the explanatory record version.
CEDAR_OUTCOME_POLICY_VERSION <- 1L

# assign point values to letter grades
grades_to_points <- data.frame(grade=c("A+","A","A-","B+","B","B-","C+","C","C-","D+","D","D-","CR","F","NC","NR","W","Drop","I"),
                               points=c(4.3,4,3.7,3.3,3,2.7,2.3,2,1.7,1.3,1,.7,0,0,0,0,0,0,0))
