message("Welcome to .Rprofile!")

# Detect execution context:
# 1. Shiny app startup - skip everything (global.R handles it)
# 2. CLI/Rscript - activate renv only, let script source what it needs
# 3. Interactive RStudio - activate renv and load full environment

# In Docker, packages are installed to the system library directly.
# Skip renv activation — it would try to download renv from CRAN and fail.
is_docker <- file.exists("/.dockerenv")

message("Detecting execution context...")

cmdline <- paste(commandArgs(), collapse = " ")
is_shiny_startup <- nzchar(Sys.getenv("SHINY_SERVER_VERSION")) ||
                    grepl("shiny", cmdline, ignore.case = TRUE)

is_cli <- !interactive() && !is_shiny_startup

if (is_shiny_startup) {
  message("Shiny app startup detected - activating renv only (global.R will load libraries)")
  # In Docker, packages are in the system library — skip renv activation.
  if (!is_docker && file.exists("renv/activate.R")) {
    source("renv/activate.R")
  }

} else if (is_cli) {
  message("CLI/Rscript execution detected - activating renv only")
  if (!is_docker && file.exists("renv/activate.R")) {
    source("renv/activate.R")
    message("Activated renv for CLI.")
  }
  # Don't load libraries or data - let the CLI script control what it needs
  
} else if (interactive()) {
  message("Interactive RStudio session detected - loading full environment")
  # Handle renv activation for interactive use
  if (file.exists("renv/activate.R")) {
    message("Found renv/activate.R. Activating renv...")
    source("renv/activate.R")
    message("Activated renv.")
  }


    message(".Rprofile is running interactively in RStudio.")
    message("Loading libraries...")
    pacman::p_load(tidyverse, dplyr, fs, qs, optparse, plotly)
    message("Loaded libraries.")

    message(".Rprofile is loading external functions...")
    
    source("config/config.R")
    message("Loaded config.R.")
    
    source("R/trunk/load-funcs.R")
    message("Loaded load-funcs.R. About to run it...")
    load_funcs("./")
    message("Ran load_funcs().")

    resolve_conflicts() # defined in utils, loaded by load_funcs
    message("Ran resolve_conflicts().")

    load_global_data(opt=NULL)
    message("Ran load_global_data().")
}

message(".Rprofile has finished loading.")
