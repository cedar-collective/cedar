# define list of passing grades, used for computing earned credit hours
# passing_grades <- c("A+","A","A-","B+","B","B-","C+","C","C-","D+","D","D-","CR")
passing_grades <- c("A+","A","A-","B+","B","B-","C+","C","CR")

# Analytics grade constants — used by classify_grades() and cone outcome logic.
# Includes retake variants (prefix R) and credit/pass equivalents.
# GRADES_DFW: outcomes that count as a DFW for retention/analytics purposes
GRADES_DFW  <- c("D", "D+", "D-", "F", "W",
                  "RD", "RD+", "RD-", "RF")

# GRADES_PASS: outcomes that count as passing for analytics purposes (C or better for UNM gateway courses)
GRADES_PASS <- c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-",
                  "CR", "P", "S",
                  "RA+", "RA", "RA-", "RB+", "RB", "RB-", "RC+", "RC", "RC-", "RCR")

# assign point values to letter grades
grades_to_points <- data.frame(grade=c("A+","A","A-","B+","B","B-","C+","C","C-","D+","D","D-","CR","F","NC","NR","W","Drop","I"),
                               points=c(4.3,4,3.7,3.3,3,2.7,2.3,2,1.7,1.3,1,.7,0,0,0,0,0,0,0))

# AUD (audit) students receive no grade and should not appear in DFW calculations.
# They are neither passing nor failing — exclude them before categorize_grades().
# Observed in data: ~127 DG/DW-status students carry "AUD" as their final_grade.
