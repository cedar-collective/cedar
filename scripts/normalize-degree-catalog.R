#!/usr/bin/env Rscript
# Local versioned drafts first. This tool performs no model or network calls.
# prepare --analysis ANALYSIS --programs ID,ID --output REVIEW_ROOT
# import --root REVIEW_ROOT --program KEY --unit KEY --response FILE --model NAME
args <- commandArgs(trailingOnly = TRUE)
usage <- paste("Usage: Rscript --vanilla scripts/normalize-degree-catalog.R COMMAND [options]",
  "prepare --analysis DIRECTORY --programs ID,ID --output REVIEW_ROOT [--institution ID]",
  "import --root REVIEW_ROOT --program PACKET_KEY --unit UNIT_KEY --response FILE --model NAME",
  "stage --root REVIEW_ROOT --drafts DIRECTORY --capture-root CAPTURE_ROOT",
  "Prepared packets are shown in Admin > Data & Usage > Catalog Review > Program review.", sep = "\n")
if (!length(args) || args[1] %in% c("--help", "-h")) { cat(usage, "\n"); quit(status = 0) }
command <- args[1]; args <- args[-1]; opts <- list()
allowed <- switch(command, prepare = c("--analysis", "--programs", "--output", "--institution"),
  stage = c("--root", "--drafts", "--capture-root"),
  import = c("--root", "--program", "--unit", "--response", "--model"), stop(usage, call. = FALSE))
while (length(args)) {
  if (!args[1] %in% allowed || args[1] %in% names(opts) || length(args) < 2L || startsWith(args[2], "--")) stop(usage, call. = FALSE)
  opts[[args[1]]] <- args[2]; args <- args[-c(1L, 2L)]
}
required <- setdiff(allowed, "--institution")
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
} else if (command == "stage") {
  keys <- stage_catalog_normalization_drafts(opts[["--root"]], opts[["--drafts"]], opts[["--capture-root"]])
  message("Validated versioned drafts: ", length(keys), "; human approvals unchanged")
} else {
  program <- load_catalog_normalization_program(opts[["--root"]], opts[["--program"]])
  unit <- catalog_normalization_unit(program, opts[["--unit"]])
  key <- import_catalog_normalization(opts[["--root"]], unit, opts[["--response"]], opts[["--model"]])
  message("Imported unreviewed proposal: ", key)
}
