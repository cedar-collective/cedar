# Helper file to load CEDAR R functions before tests run
# Files prefixed with "helper-" are sourced by testthat before running tests

# Load additional required packages
suppressPackageStartupMessages({
  library(stringr)
  library(ggplot2)
})

# Set required global variables
cedar_base_dir <<- normalizePath(file.path(dirname(getwd()), ".."))
cedar_data_dir <<- file.path(cedar_base_dir, "data")
cedar_output_dir <<- file.path(cedar_base_dir, "output")

message("Loading CEDAR functions from: ", cedar_base_dir)

# Source function loader and load all functions
source(file.path(cedar_base_dir, "R", "branches", "load-funcs.R"))
load_funcs(cedar_base_dir)

message("CEDAR functions loaded successfully")
