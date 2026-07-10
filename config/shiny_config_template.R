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

# Has registration for the next term actually opened (compared to the current
# term set above)? Drives the default term on the registration-facing tabs
# (Open Seats, Waitlists, Cancellations, Regstats): FALSE = default to the
# current term; TRUE = default to the next term students are registering for.
# Leave FALSE until registration truly opens so preliminary schedule builds
# don't present half-built next-term data as if it were real. In spring the
# next term is Summer until mid-June, then Fall (see get_default_reg_term()).
cedar_registration_underway <- FALSE

# Minimum group size for descriptive breakdowns (small-cell suppression).
# Pathways and similar analytics hide any group/pathway smaller than this so
# students can't be identified from low counts. Raise for stricter privacy;
# lower (e.g. to 3) to surface smaller patterns.
cedar_min_group_size <- 5

cedar_regstats_thresholds <- list()
cedar_regstats_thresholds[["min_impacted"]] <- 20 # min difference b/w enrollment and mean (= number of students affected)
cedar_regstats_thresholds[["pct_sd"]] <- 1 # percent of students outside the mean compared to standard deviation
cedar_regstats_thresholds[["chronic_fill_rate"]] <- 0.90 # fill rate above which a course is considered chronically capacity-constrained
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
