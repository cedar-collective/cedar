# Registration status codes used throughout CEDAR
# Source: UNM Banner registration system

# Currently registered
# RE = enrolled, RS = re-enrolled/section change, RR = registered via reserve/restricted seat
STATUS_REGISTERED  <- c("RE", "RS", "RR")

# Waitlisted (not yet enrolled)
STATUS_WAITLIST    <- c("WL")

# Early drops (before drop deadline, no grade record)
STATUS_DROP_EARLY  <- c("DR")

# Late drops (after deadline, with grade consequence)
STATUS_DROP_LATE   <- c("DG", "DW")

# All drops combined
STATUS_DROP_ALL    <- c("DR", "DG", "DW")

# Administrative/other drops
STATUS_DROP_OTHER  <- c("DD")

# Note: students with DG or DW status codes predominantly receive "W" as their
# final_grade. A small number (~127 observed) carry "AUD" (audit) — those students
# should be excluded from DFW calculations entirely (neither passing nor failing).

# instructor_name values that mean "no instructor assigned". Banner emits
# "NA, NA" (null last, null first) or an empty string for unstaffed sections.
# Combined with is.na(), this identifies shell/placeholder sections — see
# drop_shell_sections() in R/branches/enrl.R.
NO_INSTRUCTOR_NAMES <- c("NA, NA", "")
