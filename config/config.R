Sys.setenv("shiny" = FALSE)

cedar_use_small_data <- FALSE  # or FALSE for production

# Data serialization format: "qs" (faster, recommended) or "rds" (base R, fallback)
cedar_use_qs <- TRUE

############ data locations
cedar_base_dir <- "/Users/fwgibbs/Dropbox/projects/cedar/"
cedar_output_dir <- paste0(cedar_base_dir,"output/")
cedar_data_dir <- paste0(cedar_base_dir,"data/")

# used by parse-data.R to find MyReports downloads
cedar_myreports_local_dir <- "/Users/fwgibbs/Dropbox/projects/shared-data/"
cedar_shared_data_dir <- "/Users/fwgibbs/Dropbox/projects/shared-data/"
cedar_data_docker_dir <- "./data/"



############ Archiving MyReports downloads
# if you want to archive processed downloaded MyReports, update the following:
# set to NULL (no quotes) to skip archiving MyReports downloads
cedar_data_archive_dir <- NULL


############ Terms
cedar_current_term <- 202610

# these control how much data appears on dept-reports
cedar_report_start_term <- 202180
cedar_report_end_term <- 202580

# registration underway for next term (compared to current term set above)
cedar_registration_underway <- FALSE


########### Thresholds for various reports
cedar_regstats_thresholds <- list()
cedar_regstats_thresholds[["min_impacted"]] <- 15 # min difference b/w enrollment and mean (= number of students affected) 
cedar_regstats_thresholds[["pct_sd"]] <- .5 # percent of students outside the mean compared to standard deviation
cedar_regstats_thresholds[["min_squeeze"]] <- .3 # squeeze is ratio of avail seats to  mean attrition
cedar_regstats_thresholds[["min_wait"]] <- 20 # min number of students on waitlist before being flagged
cedar_regstats_thresholds[["section_proximity"]] <- .3 # how close to integer before rounding up/down for recommended sections? closer to .5 reduces -100s

cedar_report_palette <- "Spectral"

rstudio_pandoc <- "/usr/local/bin/"