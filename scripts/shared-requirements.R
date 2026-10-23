#!/usr/bin/env Rscript
# Offline reference validation/rendering and pinned-source recapture.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || !args[1] %in% c("check", "render", "recapture")) {
  stop("Usage: Rscript --vanilla scripts/shared-requirements.R check|render|recapture RULE_DIRECTORY [CAPTURE_DIRECTORY]", call. = FALSE)
}
source("R/trunk/source-snapshots.R")
source("R/branches/shared-requirements.R")
source("R/features/shared-requirements.R")
reference <- read_shared_requirement_bundle(args[2], if (args[1] == "check" && length(args) >= 3L) args[3] else NULL)
if (args[1] == "render") {
  cat(format_shared_requirement_preview(reference), "\n")
} else if (args[1] == "recapture") {
  if (length(args) != 3L) stop("recapture requires a new output directory", call. = FALSE)
  candidate <- capture_shared_requirement_sources(reference, args[3])
  changed <- names(Filter(identity, Map(function(old, new) !identical(old$sha256, new$sha256),
    reference$provenance$sources, candidate$sources)))
  cat("Captured pinned-edition source candidates. Changed sources:",
    if (length(changed)) paste(changed, collapse = ", ") else "none", "\nAuthored rules were not changed.\n")
} else {
  cat(length(reference$sets), "rule sets;", sum(vapply(reference$sets, function(x) length(x$rules), integer(1))),
    "top-level rules;", nrow(reference$memberships), "explicit Gen Ed memberships;",
    length(reference$bundle$profiles), "program profiles.\nSource bytes verified:", reference$source_bytes_verified, "\n")
}
