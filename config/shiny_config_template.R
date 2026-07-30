# Copy this file to config/shiny_config.R and adjust values as needed for your environment.

cedar_base_dir <- "./"

cedar_use_small_data <- TRUE  # set FALSE for production

# Data serialization format: "qs" (faster, recommended) or "rds" (base R, fallback)
cedar_use_qs <- TRUE

# recommended to keep as is, but you can specify other folders you've created
cedar_data_dir <- file.path(cedar_base_dir, "data")
cedar_output_dir <- file.path(cedar_base_dir, "output")

# define the current term
cedar_current_term <- 202680

# App-wide default for term inputs. Keep explicit when the preferred landing
# term differs from calendar/current-term logic.
cedar_default_term <- 202680

# Oldest term loaded into the app. Data before this term is dropped at startup
# to keep reports, filters, and caches scoped to the intended history window.
cedar_min_term <- 201980  # Fall 2019

# First term shown in department and course history views.
cedar_report_start_term <- 202180

# cedar_report_end_term is derived automatically in global.R after load_funcs():
#   cedar_report_end_term <- subtract_term(cedar_current_term)
# This keeps history views focused on complete terms while current/future-term
# surfaces can still use cedar_current_term and cedar_default_term.

# Registration timing flag for future calendar-derived defaults. Term inputs
# currently use cedar_default_term above.
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
cedar_regstats_thresholds[["min_sat_terms"]] <- 3 # min prior same-type terms at/above chronic fill before a course is flagged chronic
cedar_regstats_thresholds[["min_wait"]] <- 20 # min number of students on waitlist before being flagged

cedar_report_palette <- "Spectral"

# Logging configuration
cedar_logging_enabled <- TRUE
cedar_log_dir <- file.path(cedar_data_dir, "logs")
cedar_log_file <- file.path(cedar_log_dir, paste0("cedar_usage_", format(Sys.Date(), "%Y%m"), ".log"))
cedar_log_level <- "INFO"  # DEBUG, INFO, WARN, ERROR
cedar_log_retention_days <- 90  # Keep logs for 90 days

rstudio_pandoc <- NULL
