# Keep today's registration counts for every term still in registration.
#
#   Rscript --vanilla scripts/record-registration-snapshot.R [--output DIR]
#
# Run by update-data.sh after each successful refresh. Writes one file per term
# per pair of class-list and schedule pulls to output/registration-snapshots/
# (default), for every term in registration or scheduled ahead of it, and
# leaves a pair already recorded alone. The counts are per course, campus and
# part of term, with no student ID; why they are kept:
# R/branches/registration-snapshots.R.

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
  recorded <- record_registration_snapshot(cedar_students, cedar_sections, output_dir)
  for (i in seq_len(nrow(recorded))) {
    message(sprintf("[registration-snapshots] %s, class list %s, schedule %s: %s (%d rows) %s",
                    fmt_term(recorded$term[[i]]), format(recorded$classlist_as_of[[i]]),
                    format(recorded$sections_as_of[[i]]), recorded$status[[i]],
                    recorded$rows[[i]], recorded$path[[i]]))
  }
  invisible(recorded)
}


if (sys.nframe() == 0L) {
  record_registration_snapshot_cli(commandArgs(trailingOnly = TRUE))
}
