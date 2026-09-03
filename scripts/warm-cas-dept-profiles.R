#!/usr/bin/env Rscript

# Backward-compatible entry point. Dept Trends now warms every main analytical
# tab through the generic production warmer; the default college scope remains
# Arts & Sciences (AS/ARTS), matching this script's former CAS-only behavior.
message("[warm-cas-dept-profiles] Delegating to warm-dept-trends-cache.R")
if (!nzchar(Sys.getenv("CEDAR_TRENDS_WARM_COLLEGES", unset = ""))) {
  Sys.setenv(CEDAR_TRENDS_WARM_COLLEGES = "AS,ARTS")
}

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
base_dir <- if (length(script_arg) > 0) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1]])), ".."))
} else if (basename(getwd()) == "scripts") {
  normalizePath("..")
} else {
  normalizePath(getwd())
}
source(file.path(base_dir, "scripts", "warm-dept-trends-cache.R"))
