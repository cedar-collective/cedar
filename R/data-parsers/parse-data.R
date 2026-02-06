# parse-data.R
# This script processes various MyReports data files, parses them, and saves the results. 
# It is designed to be run from the command line or as a Plumber API endpoint.

# Default behavior is to process all .xlsx files in the MyReports downloads directory,
# parse them according to the specifications defined in report_specs, and save the results
# as Rds files in the specified data directory. It can also archive the original .xlsx
# files if archiving is enabled in the configuration.

# Activate renv for reproducible environment (skip if already active)
tryCatch({
  if (requireNamespace("renv", quietly = TRUE) && !nzchar(Sys.getenv("RENV_PROJECT"))) {
    renv::activate()
  }
}, error = function(e) {
  warning("renv activation failed; using system packages")
})

# Timestamped logging helper
base_message <- message
log_message <- function(...) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  msg <- paste0(...)
  base_message(sprintf("[parse-data.R] [%s] %s", ts, msg))
}

# use timestamped logging for this script
message <- log_message

# Summary tracking helper
summary_env <- new.env(parent = emptyenv())
summary_env$start_time <- Sys.time()
summary_env$end_time <- NULL
summary_env$run_status <- "running"
summary_env$base_dir <- NULL
summary_env$data_dir <- NULL
summary_env$reports <- list()
summary_env$errors <- character()

ensure_report <- function(report) {
  if (is.null(summary_env$reports[[report]])) {
    summary_env$reports[[report]] <- list(
      files_found = character(),
      files_processed = character(),
      files_deleted = character(),
      file_details = list(),
      errors = character()
    )
  }
}

add_file_details <- function(report, file, rows_old, rows_new, rows_final, as_of_date) {
  ensure_report(report)
  file_key <- basename(file)
  summary_env$reports[[report]]$file_details[[file_key]] <- list(
    rows_old = rows_old,
    rows_new = rows_new,
    rows_final = rows_final,
    as_of_date = as_of_date
  )
}

add_error <- function(msg, report = NULL) {
  if (is.null(report)) {
    summary_env$errors <- c(summary_env$errors, msg)
  } else {
    ensure_report(report)
    summary_env$reports[[report]]$errors <- c(summary_env$reports[[report]]$errors, msg)
  }
}

set_files_found <- function(report, files) {
  ensure_report(report)
  summary_env$reports[[report]]$files_found <- unique(c(summary_env$reports[[report]]$files_found, files))
}

add_file_processed <- function(report, file) {
  ensure_report(report)
  summary_env$reports[[report]]$files_processed <- unique(c(summary_env$reports[[report]]$files_processed, file))
}

add_file_deleted <- function(report, file) {
  ensure_report(report)
  summary_env$reports[[report]]$files_deleted <- unique(c(summary_env$reports[[report]]$files_deleted, file))
}

write_summary <- function() {
  data_dir <- if (is.null(summary_env$data_dir)) {
    if (is.null(summary_env$base_dir)) getwd() else file.path(summary_env$base_dir, "data")
  } else {
    summary_env$data_dir
  }
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  summary_file <- file.path(data_dir, "parse-data-summary.log")

  fmt_time <- function(x) {
    if (is.null(x) || is.na(x)) return("NA")
    format(x, "%Y-%m-%d %H:%M:%S")
  }

  lines <- c(
    "---- parse-data summary ----",
    paste0("Run start: ", fmt_time(summary_env$start_time)),
    paste0("Run end: ", fmt_time(summary_env$end_time)),
    paste0("Status: ", summary_env$run_status)
  )

  if (length(summary_env$errors) > 0) {
    lines <- c(lines, "Global errors:", paste0("  - ", summary_env$errors))
  }

  report_names <- names(summary_env$reports)
  if (length(report_names) == 0) {
    lines <- c(lines, "Reports: none")
  } else {
    lines <- c(lines, "Reports:")
    for (report in report_names) {
      rpt <- summary_env$reports[[report]]
      files_found <- if (length(rpt$files_found) == 0) "none" else paste(rpt$files_found, collapse = ", ")
      files_processed <- if (length(rpt$files_processed) == 0) "none" else paste(rpt$files_processed, collapse = ", ")
      files_deleted <- if (length(rpt$files_deleted) == 0) "none" else paste(rpt$files_deleted, collapse = ", ")

      lines <- c(
        lines,
        paste0("  - ", report),
        paste0("    Files found (", length(rpt$files_found), "): ", files_found),
        paste0("    Files processed (", length(rpt$files_processed), "): ", files_processed),
        paste0("    Files deleted (", length(rpt$files_deleted), "): ", files_deleted)
      )

      if (length(rpt$file_details) > 0) {
        lines <- c(lines, "    File Details:")
        for (file_key in names(rpt$file_details)) {
          details <- rpt$file_details[[file_key]]
          lines <- c(
            lines,
            paste0("      - ", file_key),
            paste0("        Rows in old data: ", details$rows_old),
            paste0("        Rows read from new data: ", details$rows_new),
            paste0("        Rows in combined output: ", details$rows_final),
            paste0("        As of date: ", details$as_of_date)
          )
        }
      }

      if (length(rpt$errors) > 0) {
        lines <- c(lines, "    Errors:", paste0("      - ", rpt$errors))
      }
    }
  }

  lines <- c(lines, "")
  write(lines, file = summary_file, append = TRUE)
}

# define details for each kind of MyReports report
message("defining report specifications...")
report_specs <- list(
  desr = list(
    data_file = "DESRs",
    term_col = "TERM",
    parser = "parse-DESR.R",
    filename_sig = "Department_Enrollment_Status"
  ),
  cl = list(
    data_file = "class_lists",
    term_col = "Academic Period",
    ID_col = c("Primary Instructor ID", "Student ID"),
    parser = "parse-class-list.R",
    filename_sig = "Class_List_Guided_Adhoc"
  ),
  as = list(
    data_file = "academic_studies",
    term_col = "Academic Period",
    ID_col = "ID",
    parser = "parse-academic-study.R",
    filename_sig = "Academic_Study_Detail_Guided"
  ),
  deg = list(
    data_file = "degrees",
    term_col = "Academic Period",
    ID_col = "ID",
    parser = "parse-degrees.R",
    filename_sig = "Graduates_and_Pending_Graduates"
  )
)

# Function to check if running in Docker
is_docker <- function() {
  file.exists("/.dockerenv") ||
    (file.exists("/proc/1/cgroup") && any(grepl("docker|containerd", readLines("/proc/1/cgroup"))))
}


# Helper function to check memory usage and warn if high
check_memory <- function(context = "") {
  mem_info <- gc(verbose = FALSE)
  mem_used_mb <- sum(mem_info[, 2])  # Memory used in MB
  
  if (mem_used_mb > 1500) {  # Warn if using more than 1.5GB
    message("WARNING: High memory usage (", round(mem_used_mb, 0), " MB) at: ", context)
    gc(verbose = FALSE)  # Force garbage collection
  }
  
  return(mem_used_mb)
}


#' process_reports
#'
#' Main function to process MyReports data files.
#' - Loads configuration and required packages.
#' - Determines environment (Docker/local) and sets directories.
#' - Finds and processes .xlsx files for specified report types.
#' - Converts Excel files to CSV, parses data, and saves results as Rds.
#' - Handles encryption of sensitive ID columns.
#' - Designed for command line use.
#'
#' @param report Character vector of report types to process (e.g., "desr", "cl", "as", "deg").
#' @param guide Logical; if TRUE, prints usage instructions.
#' @return None. Side effects: saves processed data, prints progress messages.
process_reports <- function(
  report = NULL,
  guide = FALSE,
  keep_file = FALSE
){

message("Welcome to process_reports!")

# uncoment for studio testing...
# report <- list("desr")

# Load required packages (install if missing)
packages_needed <- c("cellranger", "tidyverse", "readxl", "fs", "data.table", "lubridate", "qs", "digest")
for (pkg in packages_needed) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message("Installing ", pkg, "...")
    install.packages(pkg, repos = "http://cran.us.r-project.org")
  }
}

library(cellranger)
library(tidyverse)
library(readxl)
library(fs)
library(data.table)
library(lubridate)
library(qs)
library(digest)

# set base dir
message("Setting base dir...")
if (is_docker()) {
  base_dir <- "./"
} else {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else NA_character_
  if (is.na(script_path) || script_path == "") {
    script_path <- tryCatch(normalizePath(sys.frames()[[1]]$ofile), error = function(e) NA_character_)
  }
  script_dir <- if (!is.na(script_path) && script_path != "") {
    dirname(normalizePath(script_path))
  } else {
    getwd()
  }
  message("script_dir resolved to: ", script_dir)
  base_dir <- normalizePath(file.path(script_dir, "..", ".."), mustWork = FALSE)
}
message("base dir set to: ", base_dir)
summary_env$base_dir <- base_dir

config_dir <- file.path(base_dir, "config")
message("setting config directory to: ", config_dir)

R_dir <- file.path(base_dir, "R")
message("setting R directory to: ", R_dir)

parsers_dir <- file.path(base_dir, "R", "data-parsers")
message("setting parsers directory to: ", parsers_dir)


if (is_docker()) {
  message("Docker environment detected, so loading shiny_config.R...")
  source(file.path(config_dir, "shiny_config.R"))
} else {
  message("NOT in docker, so loading config.R...")
  source(file.path(config_dir, "config.R"))
}

message("sourcing include files...")
source(file.path(R_dir,"lists/mappings.R"))
source(file.path(R_dir,"lists/terms.R"))
source(file.path(R_dir,"lists/gen_ed_courses.R"))
source(file.path(R_dir,"branches/utils.R"))
source(file.path(R_dir,"branches/filter.R"))
source(file.path(R_dir,"branches/data.R"))
# convert report to list
report_list <- convert_param_to_list(report)

message("Determining MyReports downloads directory...")
if (is_docker()) {
  myreports_dir <- "./data/"
} else {
  myreports_dir <- cedar_myreports_local_dir
}
message("MyReports directory set to: ", myreports_dir)


message("Looking for .xlsx files in data directory: ", myreports_dir)
if (!dir.exists(myreports_dir)) {
  add_error(paste0("ERROR: Data directory does not exist: ", myreports_dir))
  stop("[parse-data.R] ERROR: Data directory does not exist: ", myreports_dir)
}

# Get all relevant .xlsx files in the MR downloads directory
message("getting list of files to process...")
file_list <- list.files(myreports_dir, pattern = "\\.xlsx$", full.names = TRUE)
if (length(file_list) == 0) {
    message("No .xlsx files found in: ", myreports_dir, ".")
  } else {
    message("Found ", length(file_list), " total .xlsx files.")
  }

# loop through reports as specified in command line
message("processing reports: ", paste(report_list, collapse = ", "))

for (report in report_list) {
  # for studio testing
  # report <- report_list[[1]]
  
  message("processing report type: ", report)

  # get report specs
  message("Getting report specs...")
  if (!report %in% names(report_specs)) {
    add_error(paste0("ERROR: Invalid report type specified: ", report, ". Valid options are: ",
                     paste(names(report_specs), collapse = ", ")),
              report = report)
    stop("[parse-data.R] ERROR: Invalid report type specified: ", report, ". Valid options are: ",
         paste(names(report_specs), collapse = ", "), call.=FALSE)
  }
  report_spec <- report_specs[[report]]
  
  # Filter files by filename signature
  sig <- report_spec$filename_sig
  sig_list <- file_list[grepl(sig, basename(file_list), ignore.case = TRUE)]
  set_files_found(report, sig_list)

  # If no relevant files found, print a message
  if (length(sig_list) == 0) {
    message("No .xlsx files found in: ", myreports_dir, " matching signature: ", sig)
  } else {
    message("Found ", length(sig_list), " .xlsx files.")
  }

  # Process each file in the list of report type
  for (file in sig_list) {
    # uncomment for studio testing
    # file <- file_list[1]

    message("\nProcessing file: ", file, "..." )

    # TODO: recognize if rebuilding database by detecting no file
    message("Setting data directory...")
    if (is_docker()) {
      cedar_shared_data_dir <- "./data"
    } else {
      # cedar_shared_data_dir already set from config.R
    }
    message("cedar_shared_data_dir set to: ", cedar_shared_data_dir)
    summary_env$data_dir <- cedar_shared_data_dir

    message("Loading previous data...")
    # Use appropriate extension based on cedar_use_qs config
    ext <- get_data_extension()
    oldfile <- file.path(cedar_shared_data_dir, paste0(report_spec$data_file, ext))
    message("existing datafile: ", oldfile)

    # check if old data file exists
    rows_old <- 0
    if (file.exists(oldfile)) {
      old_data <- load_cedar_data(oldfile)
      rows_old <- nrow(old_data)
      message("Loaded ", rows_old, " rows.")
      rebuild <- FALSE
    }
    else {
      message("No previous data found.")
      old_data <- tibble()
      rebuild <- TRUE
    }

    message("Loading latest data...")

    check_memory("before loading Excel file")

    # Convert xlsx to csv using external tool (more reliable for large/complex files than readxl)
    xlsx_file <- file
    csv_file <-  file.path(cedar_shared_data_dir,paste0(report_spec$data_file,".csv"))
    message("Converting xlsx to csv: ", xlsx_file, " -> ", csv_file)

    # Run the conversion with error checking
    tryCatch({
      result <- system2("xlsx2csv", args = c(xlsx_file, csv_file), 
                       stdout = TRUE, stderr = TRUE)
      
      # Check if CSV was created and has content
      if (!file.exists(csv_file)) {
        stop("xlsx2csv did not create output file: ", csv_file)
      }
      
      if (file.size(csv_file) == 0) {
        stop("xlsx2csv created empty file: ", csv_file)
      }
      
      message("Successfully converted xlsx to csv (", 
              round(file.size(csv_file) / 1024 / 1024, 2), " MB)")
      
    }, error = function(e) {
      add_error(paste0("ERROR: xlsx2csv conversion failed for ", xlsx_file, ": ", e$message),
                report = report)
      stop("[parse-data.R] ERROR: xlsx2csv conversion failed: ", e$message, 
           "\nMake sure xlsx2csv is installed (pip install xlsx2csv)")
    })

    # Now read the CSV
    new_data <- fread(file.path(csv_file))

    new_data <- new_data %>%
      filter(
        !if_all(everything(), ~ is.na(.) | trimws(.) == "")
      )

    message("Loaded ",nrow(new_data) ," rows from CSV file.")

    check_memory("after loading CSV data")
    
    rows_new <- nrow(new_data)

    # remove any data from new term present in old data
    if (!rebuild) {
      message("Filtering out current term data in old data...")
      new_term <- unique(na.omit(new_data[[{{report_spec[["term_col"]]}}]]))
      message("New term: ", new_term)
      old_data <- old_data %>% filter(!(!!as.symbol(report_spec[["term_col"]]) %in% new_term))
      message("old_data now has ",nrow(old_data) ," rows.")
    }

    message("Adding as_of_date column...")

    # Extract download date from filename, supplied by MyReports
    file_date <- str_extract(file, "[0-9]{4}[0-9]{2}[0-9]{2}")
    
    # Add column as_of_date so we know how recent data is
    new_data$as_of_date <- ymd(file_date)
    as_of_date_value <- as.character(ymd(file_date))
    
    # source appropriate parser based on report type
    parser_file <- file.path(parsers_dir, report_spec$parser)
    message("parser file set to: ", parser_file)
    if (!file.exists(parser_file)) {
      add_error(paste0("ERROR: Parser file not found: ", parser_file), report = report)
      stop("[parse-data.R] ERROR: Parser file not found: ", parser_file)
    }
    message("Sourcing parser...")
    source(parser_file) # defines parse function for report type

    message("Parsing new data...")
    new_data <- parse(new_data)

    # encrypt student IDs if ID_col exists 
    # only encrypt new data!
    message("checking new_data for ID cols...")
    if (!is.null(report_spec) && !is.null(report_spec$ID_col) ) {
      for (col in report_spec$ID_col) {
        if (!col %in% names(new_data)) {
          add_error(paste0("ERROR: ID column not found in data: ", col), report = report)
          stop("[parse-data.R] ERROR: ID column not found in data: ", col)
        }
        message("encrypting ID column: ", col, "...")
        new_data[[col]] <- as.character(new_data[[col]])
        new_data[[col]] <- sapply(new_data[[col]], digest::digest, algo = "md5")
      } # end for each ID_col
    }
    
    
    # TODO handle different number of columns
    # meanwhile, print out the diffs for some debug info
    if (!rebuild) {
      message("cols in OLD not in NEW data")
      print(setdiff(names(old_data),names(new_data)))

      message("cols in NEW not in OLD data")
      print(setdiff(names(new_data),names(old_data)))
      
      # combine data
      message("combining new data with old data...")
      common_cols <- intersect(names(old_data), names(new_data))

      # Convert to data.table for memory-efficient operations
      old_dt <- as.data.table(old_data)
      new_dt <- as.data.table(new_data)
      rm(old_data, new_data)
      gc(verbose = FALSE)  # Reclaim memory after removing large objects

      for (col in common_cols) {
        # If either is character, coerce both to character
        if (is.character(old_dt[[col]]) || is.character(new_dt[[col]])) {
          old_dt[, (col) := as.character(get(col))]
          new_dt[, (col) := as.character(get(col))]
        }
      }
      
      # Use data.table's efficient row binding
      data <- rbindlist(list(old_dt, new_dt), use.names = TRUE, fill = TRUE)
      rm(old_dt, new_dt)
      gc(verbose = FALSE)  # Reclaim memory after combining data
      
      # Convert back to tibble if needed
      data <- as_tibble(data)
    } 
    else {
      message("No old data; no need to combine anything.")
      data <- new_data
    }
    
    rows_final <- nrow(data)
    add_file_details(report, file, rows_old, rows_new, rows_final, as_of_date_value)

    message("First 5 rows:")
    print(head(data, 5))

    message("Last 5 rows:")
    print(tail(data, 5))


    # figure out where to save the data
    if (is_docker()) {
      cedar_data_archive_dir <- NULL # no archiving in Docker
    } else { # running locally
      # everything should be set in config.R
    }

    message("Reminder: cedar_shared_data_dir set to ", cedar_shared_data_dir)

    # Use appropriate file extension based on cedar_use_qs config flag
    ext <- get_data_extension()
    data_file <- file.path(cedar_shared_data_dir, paste0(report_spec$data_file, ext))
    message("Saving data file: ", data_file, "...")

    # stop(message="stopping before actual save for testing purposes.")

    tryCatch({
      save_cedar_data(data, file = data_file)
      if (file.exists(data_file)) {
        message("File successfully saved: ", data_file)
        message("saved ",nrow(data) ," rows.")
        add_file_processed(report, file)
        if (!keep_file) {
          message("removing original .xlsx file: ", file, "...")
          removed <- file.remove(file) # remove original .xlsx file after saving
          if (isTRUE(removed)) {
            add_file_deleted(report, file)
            message("original .xlsx file removed.")
          } else {
            add_error(paste0("ERROR: Failed to remove original .xlsx file: ", file), report = report)
          }
        } else {
          message("keeping original .xlsx file: ", file)
        }
      } else {
        add_error(paste0("ERROR: File was not saved: ", data_file), report = report)
        message("ERROR: File was not saved: ", data_file)
      }
    }, error = function(e) {
      add_error(paste0("ERROR during save for ", data_file, ": ", e$message), report = report)
      message("ERROR during save: ", e$message)
    })


    # if data archiving enabled, archive downloaded file to archive folder
    # defined in config.R (or shiny-config.R)
    if (exists("cedar_cloud_data_dir") && !is.null(cedar_data_archive_dir)) {
      archive_dir <- file.path(cedar_data_archive_dir, report_spec$dir)
      message("moving .xlsx file to archive folder: ", archive_dir, "...")
      
      filepath <- as.character(file)
      
      file.copy(to =   paste0(archive_dir, basename(filepath)),
                from = filepath)
      #file.remove(from = filepath)

      message("xlsx file archived.")
    } else {
      message("No archiving directory specified; skipping archiving of data files.")
    } # end if archiving data files
    
    message("Done processing file: ", file)
  } # end process excel file
  
  message("Finished processing report type: ", report)
} # end report loop

message("All done in process_reports!")
} # end process_reports function



# ---- MAIN ---------
message("Welcome to parse-data!")
message("Setting up option parser...")
# Try to load optparse, install if needed
if (!requireNamespace("optparse", quietly = TRUE)) {
  message("Installing optparse...")
  install.packages("optparse", repos = "http://cran.us.r-project.org")
}
library(optparse)
option_list = list(
  make_option(c("-r","--report"), help="specifies what report to process. separate by commas without spaces if multiple. default is all (desr, cl, as, deg).", metavar="character"),
  make_option(c("--guide"), default=FALSE, action="store_true", help="show instructions and options for specified function."),
  make_option(c("--keep"), default=FALSE, action="store_true", help="keep original .xlsx file after processing (default: FALSE).")
)
opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)
message("Parsed options: ", str(opt))

# check if report is specified
if (is.null(opt$report) || opt$report == "") {
  message("No report specified. Using all (desr, cl, as, deg) by default.")
  opt$report <- names(report_specs) 
} else {
  message("Processing report(s): ", opt$report)
}

# check if guide is requested
if (opt$guide) {
  message("Showing guide for process_reports function...")
  message("Available reports: ", paste(names(report_specs), collapse = ", "))
  message("Use --report to specify which report(s) to process.")
  message("Use --keep to keep original .xlsx files (default removes them).")
}

# Call the function with command line arguments
tryCatch({
  process_reports(
    report = opt$report,
    guide = opt$guide,
    keep_file = opt$keep
  )
  summary_env$run_status <- "success"
}, error = function(e) {
  summary_env$run_status <- "error"
  add_error(paste0("ERROR: ", e$message))
  stop(e)
}, finally = {
  summary_env$end_time <- Sys.time()
  write_summary()
})

# restore default message behavior for the session
message <- base_message

# ---- END MAIN -----