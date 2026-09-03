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

message("[warm-dept-trends-cache] Starting Dept Trends cache warm")
Sys.setenv(shiny = "FALSE")

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
base_dir <- if (length(script_arg) > 0) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1]])), ".."))
} else {
  normalizePath(getwd())
}
setwd(base_dir)

config_path <- if (file.exists("config/shiny_config.R")) {
  "config/shiny_config.R"
} else {
  "config/config.R"
}
if (!file.exists(config_path)) {
  stop("[warm-dept-trends-cache] No CEDAR config file found")
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

split_env <- function(name, default = character(0)) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) return(default)
  trimws(strsplit(value, ",", fixed = TRUE)[[1]])
}

source_paths <- list()
resolve_data_path <- function(name) {
  use_small <- exists("cedar_use_small_data") && isTRUE(cedar_use_small_data)
  preferred <- file.path(cedar_data_dir, paste0(name, get_data_extension()))
  alternate <- if (grepl("\\.qs$", preferred, ignore.case = TRUE)) {
    sub("\\.qs$", ".Rds", preferred, ignore.case = TRUE)
  } else {
    sub("\\.Rds$", ".qs", preferred, ignore.case = TRUE)
  }
  candidates <- c(
    if (use_small) file.path(cedar_data_dir, paste0(name, c("_small.qs", "_small.Rds"))),
    preferred,
    alternate
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0) candidates[[1]] else existing[[1]]
}

load_object <- function(name) {
  path <- resolve_data_path(name)
  value <- load_cedar_data(path)
  if (is.null(value) || length(value) == 0) {
    stop("[warm-dept-trends-cache] Missing or empty object: ", name)
  }
  source_paths[[name]] <<- path
  value
}

data_objects <- list(
  cedar_sections = load_object("cedar_sections"),
  cedar_students = load_object("cedar_students"),
  cedar_programs = load_object("cedar_programs"),
  cedar_degrees = load_object("cedar_degrees"),
  cedar_faculty = load_object("cedar_faculty"),
  cedar_lookups = load_object("cedar_lookups")
)

if (exists("cedar_min_term", inherits = TRUE)) {
  for (key in names(data_objects)) {
    if (is.data.frame(data_objects[[key]]) && "term" %in% names(data_objects[[key]])) {
      data_objects[[key]] <- dplyr::filter(
        data_objects[[key]], term >= cedar_min_term
      )
    }
  }
}

lookups <- data_objects[["cedar_lookups"]]
if ("major_code_to_name" %in% names(lookups)) {
  major_code_to_name <- lookups$major_code_to_name
}
if ("dept_name_lookup" %in% names(lookups) && nrow(lookups$dept_name_lookup) > 0) {
  dept_code_to_name <- setNames(
    lookups$dept_name_lookup$dept_name,
    lookups$dept_name_lookup$dept_code
  )
}

cedar_edges <- cedar_data_edges(
  data_objects[["cedar_students"]],
  max_term = cedar_current_term
)
cedar_report_end_term <- cedar_edges$last_enrolled_complete %||% cedar_report_end_term

cache_hash <- function(name) {
  value <- data_objects[[name]]
  path <- source_paths[[name]]
  info <- file.info(path)
  fingerprint <- list(
    path = normalizePath(path, mustWork = FALSE),
    size = unname(info$size),
    modified = as.character(info$mtime)
  )
  cedar_cache_object_hash(value, fingerprint)
}
for (name in names(data_objects)) {
  assign(paste0(name, "_hash"), cache_hash(name), envir = .GlobalEnv)
}

warm_campuses <- split_env("CEDAR_TRENDS_WARM_CAMPUSES", c("ABQ", "EA"))
warm_colleges <- split_env("CEDAR_TRENDS_WARM_COLLEGES", c("AS", "ARTS"))
warm_depts <- split_env("CEDAR_TRENDS_WARM_DEPTS")

sections_for_scope <- data_objects[["cedar_sections"]] %>%
  dplyr::filter(
    status == "A",
    term >= cedar_report_start_term,
    term <= cedar_report_end_term,
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
  stop("[warm-dept-trends-cache] No departments resolved for cache warming")
}

message("[warm-dept-trends-cache] Campuses: ", paste(warm_campuses, collapse = ", "))
message("[warm-dept-trends-cache] Departments: ", paste(warm_depts, collapse = ", "))

tab_specs <- list(
  enrl = compute_dept_enrl_tab,
  ch = compute_dept_credit_hours_tab,
  deg = compute_dept_degrees_tab,
  demo = compute_dept_demographics_tab
)
failures <- character(0)
warmed <- 0L
skipped <- 0L

for (dept in warm_depts) {
  message("[warm-dept-trends-cache] Warming ", dept, "...")
  opt <- list(
    dept_code = dept,
    campus = warm_campuses,
    current_term = as.integer(cedar_current_term),
    shiny = FALSE
  )

  base <- tryCatch({
    cached <- load_dept_headcount_cache(dept, data_objects, opt)
    if (!is.null(cached)) {
      skipped <<- skipped + 1L
      rehydrate_dept_report_base(cached, data_objects, opt)
    } else {
      value <- create_dept_report_base(data_objects, opt)
      if (!cache_dept_headcount(dept, value, data_objects, opt)) {
        stop("headcount cache write failed")
      }
      warmed <<- warmed + 1L
      value
    }
  }, error = function(e) {
    failures <<- c(failures, paste0(dept, "/hc: ", conditionMessage(e)))
    NULL
  })
  if (is.null(base)) next

  for (tab in names(tab_specs)) {
    ok <- tryCatch({
      cached <- load_dept_tab_cache(dept, tab, data_objects, opt)
      if (!is.null(cached)) {
        skipped <- skipped + 1L
      } else {
        payload <- tab_specs[[tab]](base)
        if (!cache_dept_tab(dept, tab, payload, data_objects, opt)) {
          stop("cache write failed")
        }
        warmed <- warmed + 1L
      }
      TRUE
    }, error = function(e) {
      failures <<- c(failures, paste0(dept, "/", tab, ": ", conditionMessage(e)))
      FALSE
    })
    rm(ok)
  }
  rm(base)
  gc(verbose = FALSE)
}

message(
  "[warm-dept-trends-cache] Complete: warmed ", warmed,
  " tab cache(s); skipped ", skipped, " current cache(s)"
)
if (length(failures) > 0) {
  stop("[warm-dept-trends-cache] Failures: ", paste(failures, collapse = "; "))
}
