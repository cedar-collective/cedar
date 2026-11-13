# Helper file to load CEDAR R functions before tests run
# Files prefixed with "helper-" are sourced by testthat before running tests

# Every package the tests attach is attached here, once, so a test file run on
# its own sees what it sees in the whole suite. The app attaches the same ones
# (global.R: tidyverse, shiny, bslib, plotly).
suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(tidyr)    # replace_na(), pivot_wider() used in major-changes.R, regstats.R, etc.
  library(stringr)
  library(forcats)  # fct_reorder() used in headcount.R degree plots
  library(ggplot2)
  library(plotly)   # layout() used in headcount.R, enrl.R — must be loaded to avoid graphics::layout()
  library(scales)   # needed by population-trend.R (percent_format)
  library(lubridate)
  library(withr)
  library(shiny)    # the module files sourced below build tags at load
  library(bslib)
})

# Set required global variables
cedar_base_dir <<- normalizePath(file.path(dirname(getwd()), ".."))
cedar_data_dir <<- file.path(cedar_base_dir, "data")
cedar_output_dir <<- file.path(cedar_base_dir, "output")

message("Loading CEDAR functions from: ", cedar_base_dir)

# Source function loader and load all functions
source(file.path(cedar_base_dir, "R", "trunk", "load-funcs.R"))
load_funcs(cedar_base_dir, modules = FALSE)

# Files load_funcs() leaves out that the suite tests. Module servers are never
# run here; three module files are read for the pure helpers they hold (shared
# UI helpers, Admin's view builders, Dept Trends' tab builders). The class-list
# waitlist parser and the synthetic institution's builder are scripts' parts,
# not layers.
for (.extra in c("R/modules/ui-helpers.R", "R/modules/admin.R", "R/modules/dept-trends.R",
                 "R/data-parsers/class-list-waitlists.R", "dev/demo-data.R")) {
  source(file.path(cedar_base_dir, .extra))
}
rm(.extra)

message("CEDAR functions loaded successfully")
