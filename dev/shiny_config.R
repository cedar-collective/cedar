# Fixed synthetic world: changing the calendar must not age out the demo.
cedar_demo <- TRUE
cedar_base_dir <- "./"
cedar_data_dir <- "./data"
cedar_output_dir <- "./output"
cedar_use_small_data <- FALSE
cedar_use_qs <- TRUE
cedar_current_term <- 202680L
cedar_default_term <- 202680L
cedar_min_term <- 202310L
cedar_report_start_term <- 202310L
cedar_registration_underway <- TRUE
cedar_min_group_size <- 5L
cedar_regstats_thresholds <- list(min_impacted = 20, pct_sd = 1,
  chronic_fill_rate = 0.90, min_sat_terms = 3, min_wait = 20,
  section_proximity = 0.3)
cedar_report_palette <- NULL
cedar_logging_enabled <- TRUE
cedar_log_dir <- file.path(cedar_data_dir, "logs")
cedar_log_file <- file.path(cedar_log_dir, paste0("cedar_usage_", Sys.Date(), ".log"))
cedar_log_level <- "INFO"
cedar_log_retention_days <- 90
rstudio_pandoc <- NULL
