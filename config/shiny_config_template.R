# Copy this file to config/shiny_config.R and adjust values as needed for your environment.

cedar_base_dir <- "./"

cedar_use_small_data <- TRUE  # set FALSE for production

# Data serialization format: "qs" (faster, recommended) or "rds" (base R, fallback)
cedar_use_qs <- TRUE

# recommended to keep as is, but you can specify other folders you've created
cedar_data_dir <- file.path(cedar_base_dir, "data")
cedar_output_dir <- file.path(cedar_base_dir, "output")

# define the current term
cedar_current_term <- 202610

# these term codes control how much data appears on dept-reports
cedar_report_start_term <- 202180
cedar_report_end_term <- 202560

# registration underway for next term (compared to current term set above)
cedar_registration_underway <- FALSE

cedar_regstats_thresholds <- list()
cedar_regstats_thresholds[["min_impacted"]] <- 20 # min difference b/w enrollment and mean (= number of students affected)
cedar_regstats_thresholds[["pct_sd"]] <- 1 # percent of students outside the mean compared to standard deviation
cedar_regstats_thresholds[["min_squeeze"]] <- .3 # squeeze is ratio of avail seats to mean attrition
cedar_regstats_thresholds[["min_wait"]] <- 20 # min number of students on waitlist before being flagged

cedar_forecasts_thresholds <- list()
cedar_forecasts_thresholds[["section_proximity"]] <- .3 # how close to integer before rounding up/down for recommended sections? closer to .5 reduces -100s

cedar_report_palette <- "Spectral"

# Logging configuration
cedar_logging_enabled <- TRUE
cedar_log_dir <- file.path(cedar_data_dir, "logs")
cedar_log_file <- file.path(cedar_log_dir, paste0("cedar_usage_", format(Sys.Date(), "%Y%m"), ".log"))
cedar_log_level <- "INFO"  # DEBUG, INFO, WARN, ERROR
cedar_log_retention_days <- 90  # Keep logs for 90 days

rstudio_pandoc <- NULL
