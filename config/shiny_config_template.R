# Copy this file to config/shiny_config.R and adjust values as needed for your environment.

cedar_base_dir <- "./"

cedar_use_small_data <- TRUE  # set FALSE for production

# Data serialization format: "qs" (faster, recommended) or "rds" (base R, fallback)
cedar_use_qs <- TRUE

# recommended to keep as is, but you can specify other folders you've created
cedar_data_dir <- file.path(cedar_base_dir, "data")
cedar_output_dir <- file.path(cedar_base_dir, "output")

# ── Terms ────────────────────────────────────────────────────────────────────
# Term codes are YYYYSS: 10 = Spring, 60 = Summer, 80 = Fall.
#
# Loading a new term's data needs no change here. Every term picker lists every
# term in the section data, so a schedule pulled months ahead (a preliminary
# Spring schedule in October, say) is selectable as soon as it is loaded.

# The term the institution is in now. A later term with sections but no
# enrollments is treated as upcoming: Enrollment's low-enrollment view compares
# its scheduled courses with past offerings of the same season instead of
# flagging every empty section. Enrollment's trend charts also stop here.
cedar_current_term <- 202680

# The term every term picker opens on (Enrollment, Open Seats, Waitlists,
# Cancellations, Regstats, Dept Dashboard), and the term the Dept Dashboard
# cache warmer uses. Setting it to a term with no registrations yet opens those
# tabs on a term whose enrollment counts are all still zero.
cedar_default_term <- 202680

# Oldest term loaded into the app. Data before this term is dropped at startup
# to keep reports, filters, and caches scoped to the intended history window.
cedar_min_term <- 201980  # Fall 2019

# First term shown in department and course history views.
cedar_report_start_term <- 202180

# There is no end-term setting. global.R reads the right edges (last settled,
# last graded, last enrolled) from the loaded data at startup with
# cedar_report_edges(); see the right-edge policy in AGENTS.md.

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

# NULL uses the shared CEDAR nature palette. You may supply a ColorBrewer palette
# name or explicit color vector for local experiments.
cedar_report_palette <- NULL

# Logging configuration
cedar_logging_enabled <- TRUE
cedar_log_dir <- file.path(cedar_data_dir, "logs")
cedar_log_file <- file.path(cedar_log_dir, paste0("cedar_usage_", format(Sys.Date(), "%Y%m%d"), ".log"))
cedar_log_level <- "INFO"  # DEBUG, INFO, WARN, ERROR
cedar_log_retention_days <- 90  # Archive older closed files; never delete history

rstudio_pandoc <- NULL
