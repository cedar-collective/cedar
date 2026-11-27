#!/usr/bin/env Rscript
# Local versioned drafts first. This tool performs no model or network calls.
# prepare --analysis ANALYSIS --programs ID,ID --output REVIEW_ROOT
# import --root REVIEW_ROOT --program KEY --unit KEY --response FILE --model NAME
# check --reading FILE|DIRECTORY: every problem staging and the compiler would
#   refuse in a reading, at once, before it is committed (exit 1 on any). The
#   store and archive default to $CEDAR_DATA_DIR's catalog-normalizations/ and
#   catalog-scans/ for the institution.
args <- commandArgs(trailingOnly = TRUE)
usage <- paste("Usage: Rscript --vanilla scripts/normalize-degree-catalog.R COMMAND [options]",
  "prepare --analysis DIRECTORY --programs ID,ID --output REVIEW_ROOT [--institution ID]",
  "import --root REVIEW_ROOT --program PACKET_KEY --unit UNIT_KEY --response FILE --model NAME",
  "stage --root REVIEW_ROOT --drafts DIRECTORY --capture-root CAPTURE_ROOT",
  "check --reading FILE|DIRECTORY [--root REVIEW_ROOT] [--capture-root CAPTURE_ROOT] [--institution ID]",
  "Prepared packets are shown in Admin > Data & Usage > Catalog Review > Draft interpretations.", sep = "\n")
if (!length(args) || args[1] %in% c("--help", "-h")) { cat(usage, "\n"); quit(status = 0) }
command <- args[1]; args <- args[-1]; opts <- list()
allowed <- switch(command, prepare = c("--analysis", "--programs", "--output", "--institution"),
  stage = c("--root", "--drafts", "--capture-root"),
  check = c("--reading", "--root", "--capture-root", "--institution"),
  import = c("--root", "--program", "--unit", "--response", "--model"), stop(usage, call. = FALSE))
while (length(args)) {
  if (!args[1] %in% allowed || args[1] %in% names(opts) || length(args) < 2L || startsWith(args[2], "--")) stop(usage, call. = FALSE)
  opts[[args[1]]] <- args[2]; args <- args[-c(1L, 2L)]
}
required <- if (command == "check") "--reading" else setdiff(allowed, "--institution")
if (length(setdiff(required, names(opts)))) stop(usage, call. = FALSE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
base <- normalizePath(file.path(dirname(script), ".."))
cedar_base_dir <- base
cedar_data_dir <- file.path(base, "data")
cedar_output_dir <- file.path(base, "output")
suppressPackageStartupMessages(library(dplyr))
if (!is.null(opts[["--institution"]])) Sys.setenv(CEDAR_INSTITUTION = opts[["--institution"]])
source(file.path(base, "R/trunk/load-funcs.R")); load_funcs(base, modules = FALSE)
if (command == "prepare") {
  analysis <- normalizePath(opts[["--analysis"]], mustWork = TRUE)
  payload <- load_catalog_review(dirname(analysis), basename(analysis))
  programs <- strsplit(opts[["--programs"]], ",", fixed = TRUE)[[1]]
  if (any(!nzchar(programs)) || anyDuplicated(programs)) stop("Program IDs must be nonempty and unique")
  prompt <- paste(readLines(file.path(base, "config/catalog-normalization-prompt.txt"), warn = FALSE), collapse = "\n")
  schema <- read_source_json(file.path(base, "config/catalog-normalization.schema.json"))
  for (id in programs) {
    path <- prepare_catalog_normalization(payload, id, opts[["--output"]], prompt, schema)
    message("Prepared: ", path)
  }
} else if (command == "check") {
  data_dir <- path.expand(Sys.getenv("CEDAR_DATA_DIR"))
  default_dir <- function(kind) {
    if (!nzchar(data_dir)) stop("Set CEDAR_DATA_DIR, or pass --root and --capture-root", call. = FALSE)
    file.path(data_dir, kind, cedar_institution_id())
  }
  root <- opts[["--root"]] %||% default_dir("catalog-normalizations")
  capture_root <- opts[["--capture-root"]] %||% default_dir("catalog-scans")
  reading <- opts[["--reading"]]
  if (!file.exists(reading)) stop("Not found: ", reading, call. = FALSE)
  paths <- if (dir.exists(reading)) sort(list.files(reading, pattern = "[.]json$", recursive = TRUE, full.names = TRUE)) else reading
  if (!length(paths)) stop("No reading files in ", reading, call. = FALSE)
  checks <- lapply(paths, check_catalog_reading, root = root, capture_root = capture_root)
  for (check in checks) cat(format_catalog_reading_check(check), sep = "\n")
  failing <- sum(vapply(checks, function(x) length(x$problems) > 0L, logical(1)))
  if (failing) {
    cat(failing, "of", length(checks), "readings need fixing before they are committed.\n")
    quit(status = 1)
  }
} else if (command == "stage") {
  keys <- stage_catalog_normalization_drafts(opts[["--root"]], opts[["--drafts"]], opts[["--capture-root"]])
  message("Validated versioned drafts: ", length(keys), "; human approvals unchanged")
} else {
  program <- load_catalog_normalization_program(opts[["--root"]], opts[["--program"]])
  unit <- catalog_normalization_unit(program, opts[["--unit"]])
  key <- import_catalog_normalization(opts[["--root"]], unit, opts[["--response"]], opts[["--model"]])
  message("Imported unreviewed proposal: ", key)
}
