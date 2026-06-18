#!/usr/bin/env Rscript
#
# Plumber API for the Cedar dept dashboard.
#
# Cedar data and functions are loaded ONCE at startup, so switching
# departments is fast — only the pipeline reruns per request.
#
# Usage:
#   Rscript -e "plumber::plumb('plumber.R')$run(port=8000)"
#

suppressPackageStartupMessages({
  library(plumber)
  library(dplyr)
  library(qs2)
})

# ---------------------------------------------------------------------------
# One-time setup — runs when Plumber starts, not on every request
# ---------------------------------------------------------------------------
# Locally (from cedar-obs/): ../cedar resolves to the cedar directory.
# In Docker (from /srv/shiny-server/cedar/): . is cedar itself.
cedar_app <- normalizePath(
  Sys.getenv("CEDAR_APP_DIR", unset = if (file.exists("../cedar")) "../cedar" else "."),
  mustWork = TRUE
)
cedar_data <- file.path(cedar_app, "data")

old_wd <- setwd(cedar_app)
source("config/shiny_config.R")   # sets cedar_current_term
source("R/trunk/load-funcs.R")    # defines load_funcs()
setwd(old_wd)

load_funcs(cedar_app, modules = FALSE)

message("[plumber.R] Loading cedar data...")
cedar_sections <- qs_read(file.path(cedar_data, "cedar_sections.qs"))
cedar_students <- qs_read(file.path(cedar_data, "cedar_students.qs"))
cedar_programs <- qs_read(file.path(cedar_data, "cedar_programs.qs"))
cedar_lookups  <- qs_read(file.path(cedar_data, "cedar_lookups.qs"))

dept_code_to_name <- tryCatch({
  lkp <- cedar_lookups[["dept_name_lookup"]]
  if (!is.null(lkp) && nrow(lkp) > 0) setNames(lkp$dept_name, lkp$dept_code) else character(0)
}, error = function(e) character(0))

data_objects <- list(
  cedar_sections = cedar_sections,
  cedar_students = cedar_students,
  cedar_programs = cedar_programs,
  cedar_lookups  = cedar_lookups
)

current_term <- cedar_current_term
current_term_label <- {
  yr <- current_term %/% 100L
  ss <- current_term %% 100L
  season <- switch(as.character(ss), "10" = "Spring", "80" = "Fall", "60" = "Summer", paste0("T", ss))
  paste0(season, " ", yr)
}

message("[plumber.R] Ready.")

# ---------------------------------------------------------------------------
# CORS — allows the Observable dev server (different port) to call this API
# ---------------------------------------------------------------------------
#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }
  plumber::forward()
}

# ---------------------------------------------------------------------------
# GET /dashboard?dept=HIST
# ---------------------------------------------------------------------------
#* @get /dashboard
#* @serializer json list(auto_unbox=TRUE, null="null", na="null", digits=4)
function(dept = "HIST") {
  message("[plumber.R] Building dashboard for dept: ", dept)

  d <- create_dept_dashboard_data(
    data_objects,
    opt = list(dept = dept, campus = c("ABQ", "EA"))
  )

  headcount_series <- d$headcount_series
  if (!is.null(headcount_series) && nrow(headcount_series) > 0) {
    headcount_series <- headcount_series %>%
      mutate(term_label = {
        yr <- term %/% 100L; ss <- term %% 100L
        season <- ifelse(ss == 10, "Sp", ifelse(ss == 80, "Fa", ifelse(ss == 60, "Su", paste0("T", ss))))
        paste0(season, " ", yr)
      })
  }

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  credit_hours_data <- cedar_students %>%
    filter(
      department == dept,
      final_grade %in% passing_grades,
      level %in% c("lower", "upper", "grad"),
      floor(term / 100) >= current_year - 4
    ) %>%
    group_by(term, level) %>%
    summarise(credit_hours = sum(credits, na.rm = TRUE), .groups = "drop") %>%
    mutate(
      term_label = {
        yr <- term %/% 100L; ss <- term %% 100L
        season <- ifelse(ss == 10, "Sp", ifelse(ss == 80, "Fa", ifelse(ss == 60, "Su", paste0("T", ss))))
        paste0(season, " ", yr)
      },
      level_label = case_when(
        level == "lower" ~ "Lower Division",
        level == "upper" ~ "Upper Division",
        level == "grad"  ~ "Graduate",
        TRUE ~ level
      )
    )

  donuts <- d$plots$student_donuts
  safe   <- function(x) if (is.null(x) || (is.data.frame(x) && nrow(x) == 0)) list() else x

  list(
    dept_code          = d$dept_code,
    dept_name          = d$dept_name,
    current_term       = current_term,
    current_term_label = current_term_label,

    headcount_summary    = safe(d$headcount_summary),
    headcount_series     = safe(headcount_series),
    credit_hours         = safe(credit_hours_data),

    current_enrl_vs_avg = list(
      above = safe(d$current_enrl_vs_avg$above),
      below = safe(d$current_enrl_vs_avg$below)
    ),

    new_this_term        = safe(d$new_this_term),
    missing_from_earlier = safe(d$missing_from_earlier),
    repeated_topics      = safe(d$repeated_topics),

    drop_stats = list(
      early = list(
        above    = safe(d$drop_stats$early_drops$above),
        below    = safe(d$drop_stats$early_drops$below),
        dept_avg = d$drop_stats$early_drops$dept_avg_rate
      ),
      late = list(
        above    = safe(d$drop_stats$late_drops$above),
        below    = safe(d$drop_stats$late_drops$below),
        dept_avg = d$drop_stats$late_drops$dept_avg_rate
      )
    ),

    student_composition = list(
      lower_major = safe(donuts[["lower_major_table_df"]]),
      upper_major = safe(donuts[["upper_major_table_df"]]),
      lower_class = safe(donuts[["lower_class_table_df"]]),
      upper_class = safe(donuts[["upper_class_table_df"]])
    )
  )
}
