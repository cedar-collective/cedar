# Keep today's registration counts for every term still in registration.
#
#   Rscript --vanilla scripts/record-registration-snapshot.R [--output DIR]
#
# Run by update-data.sh after each successful refresh. Writes to
# output/registration-snapshots/ (default), and leaves a set of pulls already
# recorded alone:
#   - registration-*: one file per term in registration or scheduled ahead of
#     it, per pair of class-list and schedule pulls. Counts per course, campus
#     and part of term (R/branches/registration-snapshots.R).
#   - return-*: one file per Fall or Spring term in registration, per set of
#     pulls. Which of last term's students have registered for it, by group,
#     read off cedar_student_terms (R/branches/return-snapshots.R), which the
#     gate that runs before this script has just rebuilt.
# Neither holds a student ID. The course counts are written first, so a failure
# in the return snapshot never costs them.

record_registration_snapshot_cli <- function(args) {
  repo_root <- getwd()
  while (!file.exists(file.path(repo_root, "global.R")) &&
         dirname(repo_root) != repo_root) {
    repo_root <- dirname(repo_root)
  }
  if (!file.exists(file.path(repo_root, "global.R"))) {
    stop("Could not find the CEDAR repository root.", call. = FALSE)
  }
  setwd(repo_root)
  output_dir <- file.path(repo_root, "output", "registration-snapshots")
  index <- match("--output", args)
  if (!is.na(index)) {
    if (index == length(args)) {
      stop("Usage: Rscript --vanilla scripts/record-registration-snapshot.R [--output DIR]",
           call. = FALSE)
    }
    output_dir <- args[[index + 1L]]
  }

  source(file.path(repo_root, "scripts", "cedar-repl.R"))
  recorded <- record_registration_snapshot(cedar_registrations, cedar_sections, output_dir)
  for (i in seq_len(nrow(recorded))) {
    message(sprintf("[registration-snapshots] %s, class list %s, schedule %s: %s (%d rows) %s",
                    fmt_term(recorded$term[[i]]), format(recorded$classlist_as_of[[i]]),
                    format(recorded$sections_as_of[[i]]), recorded$status[[i]],
                    recorded$rows[[i]], recorded$path[[i]]))
  }
  returning <- record_return_snapshot(cedar_registrations, cedar_student_terms, output_dir)
  for (i in seq_len(nrow(returning))) {
    message(sprintf("[registration-snapshots] %s from %s, class list %s: %s registered of %s (%d rows) %s %s",
                    fmt_term(returning$term[[i]]), fmt_term(returning$anchor_term[[i]]),
                    format(returning$classlist_as_of[[i]]),
                    format(returning$registered[[i]], big.mark = ","),
                    format(returning$students[[i]], big.mark = ","),
                    returning$rows[[i]], returning$status[[i]], returning$path[[i]]))
  }
  invisible(list(courses = recorded, returning = returning))
}


if (sys.nframe() == 0L) {
  record_registration_snapshot_cli(commandArgs(trailingOnly = TRUE))
}
