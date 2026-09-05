# Startup never installs packages or activates renv's old cache-linked library.
# Explicit setup: Rscript --vanilla scripts/r-environment.R restore
local({
  if (!grepl("UTF-?8", Sys.getlocale("LC_CTYPE"), ignore.case = TRUE)) {
    for (loc in c("C.UTF-8", "en_US.UTF-8", "en_US.utf8")) {
      if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
    }
  }

  in_docker <- file.exists("/.dockerenv")
  shiny_startup <- nzchar(Sys.getenv("SHINY_SERVER_VERSION")) ||
    grepl("shiny", paste(commandArgs(), collapse = " "), ignore.case = TRUE)

  # Docker uses the image's system library. Native sessions prefer the prepared
  # copied library, but an existing system-R workflow needs no automatic repair.
  if (!in_docker && file.exists("scripts/r-environment.R")) {
    env <- new.env(parent = globalenv())
    sys.source("scripts/r-environment.R", envir = env)
    if (env$cedar_use_native_library(required = FALSE)) {
      message("CEDAR: using the prepared native R library.")
    } else {
      message("CEDAR: using system R packages; optional pinned setup: ",
              "Rscript --vanilla scripts/r-environment.R restore")
    }
  }

  # Keep the analyst's persistent-session workflow. No data is loaded for CLI,
  # Shiny startup, or Docker (global.R / individual scripts own those paths).
  if (interactive() && !shiny_startup && !in_docker) {
    if (!file.exists("config/config.R")) {
      message("CEDAR: no local config/config.R; skipping automatic data loading. ",
              "See docs/developers/installation.md.")
    } else {
      packages <- c("tidyverse", "dplyr", "fs", "qs2", "optparse", "plotly")
      missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
      if (length(missing)) {
        message("CEDAR: missing packages: ", paste(missing, collapse = ", "),
                ". Run the explicit restore command; startup will not install them.")
      } else {
        for (package in packages) library(package, character.only = TRUE)
        source("config/config.R")
        source("R/trunk/load-funcs.R")
        load_funcs("./")
        resolve_conflicts()
        load_global_data(opt = NULL)
      }
    }
  }
})
