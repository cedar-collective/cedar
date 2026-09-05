#!/usr/bin/env Rscript
# Writes only the isolated Docker demo volume. No mrgather or institution files.
if (!identical(Sys.getenv("CEDAR_DEMO"), "true") || !file.exists("/.dockerenv")) {
  stop("Demo generation must run through bash scripts/dev.sh up inside Docker.")
}
suppressPackageStartupMessages(library(tidyverse))
source("dev/demo-data.R")
SOURCED_FROM_PARSE_DATA <- TRUE
source("R/data-parsers/transform-to-cedar.R")
target <- "/srv/shiny-server/cedar/data"
marker <- file.path(target, "synthetic-demo.txt")
dir.create(target, recursive = TRUE, showWarnings = FALSE)
if (length(list.files(target, all.files = TRUE, no.. = TRUE)) > 0L && !file.exists(marker)) {
  stop("Refusing to write into an unmarked, nonempty data directory.")
}
sources <- c("dev/demo-data.R", "dev/generate-demo.R", "dev/shiny_config.R",
             list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
             "/opt/cedar-program-map.qs")
signature <- digest::digest(tools::md5sum(sources), algo = "sha256")
outputs <- paste0("cedar_", c("sections", "students", "programs", "degrees", "faculty",
                             "lookups", "grades", "next_term", "student_term_credits", "applicants"), ".qs")
if (file.exists(marker) && identical(readLines(marker), signature) &&
    all(file.exists(file.path(target, c(outputs, "program_map.qs"))))) {
  message("Synthetic demo already matches the source; reusing it.")
  quit(status = 0)
}
# Build away from the live files. Publish only after every table exists.
stage <- tempfile("demo-build-")
dir.create(stage)
raw <- build_demo_sources()
for (nm in names(raw)) qs2::qs_save(raw[[nm]], file.path(stage, paste0(nm, ".qs")))
stopifnot(file.copy("/opt/cedar-program-map.qs", file.path(stage, "program_map.qs")))
transform_to_cedar(data_dir = stage, use_qs = TRUE)
stopifnot(all(file.exists(file.path(stage, outputs))))
writeLines("building", marker)
for (nm in c(outputs, "program_map.qs", "cedar-status.json")) {
  stopifnot(file.copy(file.path(stage, nm), file.path(target, paste0(nm, ".tmp")), overwrite = TRUE))
  stopifnot(file.rename(file.path(target, paste0(nm, ".tmp")), file.path(target, nm)))
}
writeLines(signature, marker)
message("Synthetic demo ready: 9 fixed terms, 4 departments, 7 course listings.")
