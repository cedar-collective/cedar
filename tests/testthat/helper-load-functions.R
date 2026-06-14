# Helper file to load CEDAR R functions before tests run
# Files prefixed with "helper-" are sourced by testthat before running tests

# Load additional required packages
suppressPackageStartupMessages({
  library(tidyr)    # replace_na(), pivot_wider() used in major-changes.R, regstats.R, etc.
  library(stringr)
  library(forcats)  # fct_reorder() used in headcount.R degree plots
  library(ggplot2)
  library(plotly)   # layout() used in headcount.R, enrl.R — must be loaded to avoid graphics::layout()
  library(scales)   # needed by population-trend.R (percent_format)
})

# Set required global variables
cedar_base_dir <<- normalizePath(file.path(dirname(getwd()), ".."))
cedar_data_dir <<- file.path(cedar_base_dir, "data")
cedar_output_dir <<- file.path(cedar_base_dir, "output")

message("Loading CEDAR functions from: ", cedar_base_dir)

# Source function loader and load all functions
source(file.path(cedar_base_dir, "R", "trunk", "load-funcs.R"))
load_funcs(cedar_base_dir, modules = FALSE)

message("CEDAR functions loaded successfully")
