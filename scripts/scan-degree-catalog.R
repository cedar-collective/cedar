#!/usr/bin/env Rscript
# Offline public catalog capture, extraction and comparison. No Banner data or AI key needed.
# Rscript --vanilla scripts/scan-degree-catalog.R scan --output data/catalog-scans/current
# Rscript --vanilla scripts/scan-degree-catalog.R analyze --input CAPTURE --output NEW_ANALYSIS
# Rscript --vanilla scripts/scan-degree-catalog.R compare --before OLD_ANALYSIS --after NEW_ANALYSIS --output DIFF

args <- commandArgs(trailingOnly = TRUE)
usage <- paste(
  "Usage: Rscript --vanilla scripts/scan-degree-catalog.R COMMAND [options]",
  "Commands: scan (capture + analyze), capture, analyze (offline), compare (offline)",
  "Options: --institution ID --source-id ID --catalog-id ID --output DIRECTORY",
  "         --programs-only --resume --input CAPTURE --before ANALYSIS --after ANALYSIS",
  sep = "\n")
if (!length(args) || args[1] %in% c("--help", "-h")) { cat(usage, "\n"); quit(status = 0) }
command <- args[1]; args <- args[-1]
if (!command %in% c("scan", "capture", "analyze", "compare")) stop(usage, call. = FALSE)
options <- list()
flags <- c("--programs-only", "--resume")
values <- c("--institution", "--source-id", "--catalog-id", "--output", "--input", "--before", "--after")
while (length(args)) {
  key <- args[1]
  if (key %in% names(options)) stop("Repeated option: ", key, call. = FALSE)
  if (key %in% flags) { options[[key]] <- TRUE; args <- args[-1] }
  else {
    if (!key %in% values || length(args) < 2L || startsWith(args[2], "--")) stop(usage, call. = FALSE)
    options[[key]] <- args[2]; args <- args[-c(1, 2)]
  }
}
allowed <- if (command %in% c("scan", "capture")) {
  c("--institution", "--source-id", "--catalog-id", "--output", flags)
} else if (command == "analyze") {
  c("--institution", "--input", "--output")
} else c("--institution", "--before", "--after", "--output")
if (length(setdiff(names(options), allowed))) stop("Option does not apply to ", command, ": ",
  paste(setdiff(names(options), allowed), collapse = ", "), call. = FALSE)
if (isTRUE(options[["--resume"]]) && is.null(options[["--output"]])) stop("--resume requires the original --output directory", call. = FALSE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
root <- normalizePath(file.path(dirname(script), ".."))
if (!is.null(options[["--institution"]])) Sys.setenv(CEDAR_INSTITUTION = options[["--institution"]])
cedar_base_dir <- root
cedar_data_dir <- file.path(root, "data")
cedar_output_dir <- file.path(root, "output")
source(file.path(root, "R/trunk/load-funcs.R"))
load_funcs(root, modules = FALSE)
output <- options[["--output"]]
if (command %in% c("scan", "capture")) {
  dir <- cedar_institution_dir(root)
  sources <- read_institution_file("catalog_scan_sources", dir)
  id <- options[["--source-id"]]
  if (!is.null(id)) sources <- sources[sources$source_id == id, ]
  if (nrow(sources) != 1L) stop("Select one configured --source-id", call. = FALSE)
  if (is.null(output)) output <- file.path(root, "data/catalog-scans", cedar_institution_id(),
    format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"))
  capture_degree_catalog(as.list(sources[1, ]), read_institution_file("catalog_scan_credentials", dir),
    read_institution_file("catalog_scan_fields", dir), output, catalog_id = options[["--catalog-id"]],
    include_courses = !isTRUE(options[["--programs-only"]]), resume = isTRUE(options[["--resume"]]))
  if (command == "scan") analyze_degree_catalog(output)
} else if (command == "analyze") {
  input <- options[["--input"]]
  if (is.null(input)) stop("analyze requires --input CAPTURE", call. = FALSE)
  if (is.null(output)) output <- file.path(input, "analysis")
  analyze_degree_catalog(input, output)
} else {
  before <- options[["--before"]]; after <- options[["--after"]]
  if (is.null(before) || is.null(after) || is.null(output)) stop("compare requires --before, --after, and --output", call. = FALSE)
  compare_degree_catalog_scans(before, after, output)
}
