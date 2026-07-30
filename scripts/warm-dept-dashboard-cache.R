#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(forcats)
  library(ggplot2)
  library(plotly)
  library(scales)
  library(qs2)
  library(digest)
  library(jsonlite)
})

message("[warm-dept-dashboard-cache] Starting Dept Dashboard cache warm")
Sys.setenv(shiny = "FALSE")

base_dir <- normalizePath(file.path(dirname(commandArgs(trailingOnly = FALSE)[1]), ".."),
                          mustWork = FALSE)
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_arg) > 0) {
  base_dir <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1]])), ".."))
}
setwd(base_dir)

config_path <- if (file.exists("config/shiny_config.R")) {
  "config/shiny_config.R"
} else {
  "config/config.R"
}
if (!file.exists(config_path)) {
  stop("[warm-dept-dashboard-cache] No config file found at config/shiny_config.R or config/config.R")
}
source(config_path)

if (!exists("cedar_base_dir", inherits = TRUE) || is.null(cedar_base_dir)) {
  cedar_base_dir <- base_dir
}
cedar_base_dir <- normalizePath(cedar_base_dir)

if (!exists("cedar_data_dir", inherits = TRUE) || is.null(cedar_data_dir)) {
  cedar_data_dir <- file.path(cedar_base_dir, "data")
}
cedar_data_dir <- normalizePath(cedar_data_dir, mustWork = FALSE)

source(file.path(cedar_base_dir, "R", "trunk", "load-funcs.R"))
load_funcs(cedar_base_dir, modules = FALSE)

cedar_report_end_term <- subtract_term(cedar_current_term)

split_env <- function(name, default = character(0)) {
  val <- Sys.getenv(name, unset = "")
  if (!nzchar(val)) return(default)
  trimws(strsplit(val, ",", fixed = TRUE)[[1]])
}

load_table <- function(name) {
  path <- file.path(cedar_data_dir, paste0(name, get_data_extension()))
  tbl <- load_cedar_data(path)
  if (is.null(tbl) || nrow(tbl) == 0) {
    stop("[warm-dept-dashboard-cache] Missing or empty table: ", name)
  }
  tbl
}

data_objects <- list(
  cedar_sections = load_table("cedar_sections"),
  cedar_students = load_table("cedar_students"),
  cedar_programs = load_table("cedar_programs")
)

if (exists("cedar_min_term", inherits = TRUE)) {
  for (key in names(data_objects)) {
    if ("term" %in% names(data_objects[[key]])) {
      data_objects[[key]] <- dplyr::filter(data_objects[[key]], term >= cedar_min_term)
    }
  }
}

cedar_students_hash <- substr(digest::digest(list(
  nrow(data_objects[["cedar_students"]]),
  ncol(data_objects[["cedar_students"]])
)), 1, 8)
cedar_sections_hash <- substr(digest::digest(list(
  nrow(data_objects[["cedar_sections"]]),
  ncol(data_objects[["cedar_sections"]])
)), 1, 8)
cedar_programs_hash <- substr(digest::digest(list(
  nrow(data_objects[["cedar_programs"]]),
  ncol(data_objects[["cedar_programs"]])
)), 1, 8)

warm_campuses <- split_env("CEDAR_DASHBOARD_WARM_CAMPUSES", c("ABQ", "EA"))
warm_colleges <- split_env("CEDAR_DASHBOARD_WARM_COLLEGES", c("AS", "ARTS"))
warm_depts <- split_env("CEDAR_DASHBOARD_WARM_DEPTS")
warm_term <- Sys.getenv("CEDAR_DASHBOARD_WARM_TERM", unset = "")
warm_term <- if (nzchar(warm_term)) {
  as.integer(warm_term)
} else if (exists("cedar_default_term", inherits = TRUE)) {
  as.integer(cedar_default_term)
} else {
  as.integer(cedar_current_term)
}

sections_for_scope <- data_objects[["cedar_sections"]] %>%
  dplyr::filter(
    term == warm_term,
    status == "A",
    campus %in% warm_campuses,
    !is.na(department),
    nzchar(department)
  )

if (length(warm_depts) == 0) {
  if ("college" %in% names(sections_for_scope)) {
    sections_for_scope <- sections_for_scope %>%
      dplyr::filter(college %in% warm_colleges)
  }
  warm_depts <- sort(unique(sections_for_scope$department))
}

if (length(warm_depts) == 0) {
  stop("[warm-dept-dashboard-cache] No departments resolved for cache warming")
}

message("[warm-dept-dashboard-cache] Term: ", warm_term)
message("[warm-dept-dashboard-cache] Campuses: ", paste(warm_campuses, collapse = ", "))
message("[warm-dept-dashboard-cache] Departments: ", paste(warm_depts, collapse = ", "))

failures <- character(0)
for (dept in warm_depts) {
  message("[warm-dept-dashboard-cache] Warming ", dept, "...")
  opt <- list(
    dept = dept,
    campus = warm_campuses,
    term = warm_term,
    shiny = FALSE
  )
  ok <- tryCatch({
    dashboard <- create_dept_dashboard_data(data_objects, opt)
    save_dept_dashboard_cache(opt, dashboard, data_objects)
  }, error = function(e) {
    message("[warm-dept-dashboard-cache] Failed ", dept, ": ", conditionMessage(e))
    FALSE
  })
  if (!isTRUE(ok)) failures <- c(failures, dept)
}

if (length(failures) > 0) {
  stop("[warm-dept-dashboard-cache] Failed departments: ", paste(failures, collapse = ", "))
}

message("[warm-dept-dashboard-cache] Complete: warmed ", length(warm_depts), " department dashboard cache(s)")
