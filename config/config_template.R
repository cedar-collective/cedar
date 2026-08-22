Sys.setenv("shiny" = FALSE)

cedar_use_small_data <- FALSE  # set TRUE for lightweight local testing

# Data serialization format: "qs" (faster, recommended) or "rds" (base R, fallback)
cedar_use_qs <- TRUE

############ data locations
# Trailing slash on cedar_base_dir is optional — the sub() below normalizes it.
# Do NOT drop the trailing slash from cedar_data_dir / cedar_output_dir: the
# standalone parsers (parse-NSO.R, parse-HRreport.R) append to them with paste0().
#
# Worth getting right, because the failure is silent. If cedar_data_dir points
# somewhere that does not exist, transform-to-cedar.R skips its "copy to local
# data dir" step, reports success, and the app quietly keeps reading whatever
# stale tables are already in place. See ISSUES.md I3.
cedar_base_dir <- sub("/+$", "", "FULL PATH TO YOUR CEDAR DIRECTORY") # e.g. /home/you/cedar
cedar_output_dir <- file.path(cedar_base_dir, "output/")
cedar_data_dir <- file.path(cedar_base_dir, "data/")

# used by parse-data.R to find MyReports downloads/shared data
cedar_myreports_local_dir <- "FULL PATH TO YOUR SHARED-DATA DIRECTORY"
cedar_shared_data_dir <- "FULL PATH TO YOUR SHARED-DATA DIRECTORY"
cedar_data_docker_dir <- "./data/"


############ Archiving MyReports downloads
# if you want to archive processed downloaded MyReports, update the following:
# set to NULL (no quotes) to skip archiving MyReports downloads
cedar_data_archive_dir <- NULL

############ Terms
cedar_current_term <- 202680

# App-wide default for term inputs. Keep explicit when the preferred landing
# term differs from calendar/current-term logic.
cedar_default_term <- 202680

# these control how much data appears on dept-reports
cedar_report_start_term <- 201980
cedar_report_end_term <- 202680

# Registration timing flag for future calendar-derived defaults. Term inputs
# currently use cedar_default_term above.
cedar_registration_underway <- FALSE

########### Thresholds for various reports
cedar_regstats_thresholds <- list()
cedar_regstats_thresholds[["min_impacted"]] <- 20 # min difference b/w enrollment and mean (= number of students affected) 
cedar_regstats_thresholds[["pct_sd"]] <- 1 # percent of students outside the mean compared to standard deviation
cedar_regstats_thresholds[["chronic_fill_rate"]] <- 0.90 # fill rate above which a course is considered chronically capacity-constrained
cedar_regstats_thresholds[["min_sat_terms"]] <- 3 # min prior same-type terms at/above chronic fill before a course is flagged chronic
cedar_regstats_thresholds[["min_wait"]] <- 20 # min number of students on waitlist before being flagged
cedar_regstats_thresholds[["section_proximity"]] <- .3 # how close to integer before rounding up/down for recommended sections? closer to .5 reduces -100s

# NULL uses the shared CEDAR nature palette. You may supply a ColorBrewer palette
# name or explicit color vector for local experiments.
cedar_report_palette <- NULL

rstudio_pandoc <- "/usr/local/bin/"
