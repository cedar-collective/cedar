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
