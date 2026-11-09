# CEDAR-PLATFORM: grade vocabulary and the CEDAR-wide DFW policy
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

# Bump when classification changes: a saved cedar_attempts stamped with another
# version is rebuilt at start (attempts_is_current()). Version 1 is the first
# stamped policy and excludes late-drop AUD (DFW definition 3.0.0). This is an
# artifact compatibility check, not the explanatory record version.
CEDAR_OUTCOME_POLICY_VERSION <- 1L

# Grade points for the letter grades that carry them: what cedar_student_terms'
# quality_points and graded_hours are summed with (build_student_terms()) and
# build_gpa_timeline() divides. Anything not named here carries no points and
# no graded hours — the two must be dropped together or the denominator
# silently inflates and every affected student reads low. CR/NC, W, I, PR,
# AUD and the R-prefixed retake variants are excluded, as Banner excludes them.
CEDAR_GRADE_POINTS <- c(
  "A+" = 4.0, "A" = 4.0, "A-" = 3.7,
  "B+" = 3.3, "B" = 3.0, "B-" = 2.7,
  "C+" = 2.3, "C" = 2.0, "C-" = 1.7,
  "D+" = 1.3, "D" = 1.0, "D-" = 0.7,
  "F"  = 0.0
)
