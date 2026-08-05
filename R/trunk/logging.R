# CEDAR Shiny App Usage Logging
# Track user sessions, feature usage, and performance metrics

# Level-gated debug messaging. Fires only when cedar_log_level == "DEBUG";
# silent at INFO/WARN/ERROR (the production default). Drop-in replacement for
# message() in function bodies that should be quiet in production.
cedar_debug <- function(...) {
  if (exists("cedar_log_level", inherits = TRUE) && identical(cedar_log_level, "DEBUG")) {
    message(...)
  }
}

json_ready <- function(x) {
  if (is.data.frame(x)) return(x)

  if (is.list(x)) {
    return(lapply(x, json_ready))
  }

  if (is.atomic(x) && !is.null(names(x)) && any(nzchar(names(x)))) {
    return(as.list(x))
  }

  x
}

# Initialize logging system
init_logging <- function() {
  if (!cedar_logging_enabled) return()
  
  # Create logs directory if it doesn't exist
  if (!dir.exists(cedar_log_dir)) {
    dir.create(cedar_log_dir, recursive = TRUE)
    message("[logging.R] Created log directory: ", cedar_log_dir)
  }
  
  # Clean up old log files
  cleanup_old_logs()
  
  message("[logging.R] Logging initialized. Log file: ", cedar_log_file)
}

# Clean up old log files based on retention policy
cleanup_old_logs <- function() {
  if (!dir.exists(cedar_log_dir)) return()
  
  log_files <- list.files(cedar_log_dir, pattern = "cedar_usage_.*\\.log$", full.names = TRUE)
  cutoff_date <- Sys.Date() - cedar_log_retention_days
  
  for (log_file in log_files) {
    file_date <- file.mtime(log_file)
    if (as.Date(file_date) < cutoff_date) {
      file.remove(log_file)
      message("[logging.R] Removed old log file: ", basename(log_file))
    }
  }
}

# Core logging function
write_log <- function(level, event_type, details = NULL, session_id = NULL, user_agent = NULL) {
  if (!cedar_logging_enabled) return()
  
  # Check log level
  log_levels <- c("DEBUG" = 1, "INFO" = 2, "WARN" = 3, "ERROR" = 4)
  if (log_levels[level] < log_levels[cedar_log_level]) return()
  
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # Create log entry with essential fields only - ensure all are simple strings
  log_entry <- list(
    timestamp = as.character(timestamp),
    level = as.character(level),
    session_id = as.character(session_id %||% "unknown"),
    event_type = as.character(event_type),
    details = json_ready(details)
  )
  
  log_line <- jsonlite::toJSON(log_entry, pretty = FALSE, auto_unbox = TRUE)

  tryCatch({
    write(log_line, file = cedar_log_file, append = TRUE)
  }, error = function(e) {
    message("[logging.R] Error writing to log file: ", e$message)
  })
}

# Session tracking functions (updated for reactive context)
log_session_start_reactive <- function(session) {
  # This function should be called within a reactive context
  tryCatch({
    session_id <- session$token
    user_agent <- session$clientData$user_agent
    
    details <- list(
      url = session$clientData$url_hostname,
      protocol = session$clientData$url_protocol,
      port = session$clientData$url_port,
      pathname = session$clientData$url_pathname
    )
    
    write_log("INFO", "session_start", details, session_id, user_agent)
  }, error = function(e) {
    # Fallback if reactive values not available
    session_id <- session$token
    write_log("INFO", "session_start", list(error = "reactive_data_unavailable"), session_id, NULL)
  })
}

# Simple session end (no reactive values needed)
log_session_end <- function(session) {
  session_id <- session$token
  write_log("INFO", "session_end", NULL, session_id, NULL)
}

# Feature usage tracking
log_tab_change <- function(session, tab_name) {
  session_id <- session$token
  details <- list(tab = tab_name)
  write_log("INFO", "tab_change", details, session_id)
}

log_report_generation <- function(session, report_type, parameters = NULL) {
  session_id <- session$token
  details <- list(
    report_type = report_type,
    parameters = parameters
  )
  write_log("INFO", "report_generated", details, session_id)
}

log_data_filter <- function(session, filter_type, filter_values) {
  session_id <- session$token
  details <- list(
    filter_type = filter_type,
    filter_values = filter_values
  )
  write_log("DEBUG", "data_filter", details, session_id)
}

log_download <- function(session, file_type, filename = NULL) {
  session_id <- session$token
  details <- list(
    file_type = file_type,
    filename = filename
  )
  write_log("INFO", "file_download", details, session_id)
}

# Performance monitoring
log_performance <- function(session, operation, duration_seconds, additional_info = NULL) {
  session_id <- session$token
  details <- list(
    operation = operation,
    duration_seconds = round(duration_seconds, 3),
    additional_info = additional_info
  )
  write_log("INFO", "performance", details, session_id)
}

# Error logging
log_error <- function(session, error_message, context = NULL) {
  session_id <- session$token
  details <- list(
    error = error_message,
    context = context
  )
  write_log("ERROR", "error", details, session_id)
}

# Utility function for timing operations
time_operation <- function(expr, session, operation_name, additional_info = NULL) {
  start_time <- Sys.time()
  
  result <- tryCatch({
    eval(expr)
  }, error = function(e) {
    log_error(session, e$message, operation_name)
    stop(e)
  })
  
  end_time <- Sys.time()
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
  
  log_performance(session, operation_name, duration, additional_info)
  
  return(result)
}

# Report timing functions for performance tracking and user feedback
report_timing_log_file <- file.path(cedar_data_dir, "report_timing.csv")

# Start a timed report operation and return timing context
start_report_timer <- function(report_type, report_params = NULL) {
  timing_context <- list(
    report_type = report_type,
    report_params = report_params,
    start_time = Sys.time()
  )
  
  return(timing_context)
}

# End timer and log the results.
# cached = TRUE marks this run as a cache hit so averages for status messages
# exclude it — cache hits are fast enough to skew estimates for fresh runs.
end_report_timer <- function(timing_context, cached = FALSE) {
  end_time <- Sys.time()
  duration_sec <- as.numeric(difftime(end_time, timing_context$start_time, units = "secs"))

  # Create log entry
  timing_row <- data.frame(
    timestamp = format(timing_context$start_time, "%Y-%m-%d %H:%M:%S"),
    report_type = timing_context$report_type,
    duration_sec = duration_sec,
    cached = as.integer(cached),
    report_params = if(is.null(timing_context$report_params)) NA else jsonlite::toJSON(json_ready(timing_context$report_params), auto_unbox = TRUE),
    stringsAsFactors = FALSE
  )
  
  # Write to CSV log file
  if (!file.exists(report_timing_log_file)) {
    write.table(timing_row, report_timing_log_file, sep = ",", row.names = FALSE, col.names = TRUE, append = FALSE)
  } else {
    write.table(timing_row, report_timing_log_file, sep = ",", row.names = FALSE, col.names = FALSE, append = TRUE)
  }
  
  message(sprintf("[logging.R] %s completed in %.2f seconds (logged to %s)", 
                  timing_context$report_type, duration_sec, report_timing_log_file))
  
  return(duration_sec)
}

# Get average timing for a specific report type.
# By default excludes cache hits so the estimate reflects actual compute time.
# Set cached_only = TRUE to average only cache hits (fast path); it takes
# precedence over fresh_only. Cache hits are only distinguishable once runs are
# logged with cached = TRUE (see end_report_timer), so cached_only returns NULL
# until such rows exist.
get_average_report_time <- function(report_type, fresh_only = TRUE, cached_only = FALSE) {
  if (!file.exists(report_timing_log_file)) {
    return(NULL)
  }

  tryCatch({
    log_data <- read.csv(report_timing_log_file, stringsAsFactors = FALSE)
    type_data <- log_data[log_data$report_type == report_type, ]

    if ("cached" %in% names(type_data)) {
      if (cached_only) {
        type_data <- type_data[!is.na(type_data$cached) & type_data$cached == 1, ]
      } else if (fresh_only) {
        # NA in cached column means pre-feature rows — treat as fresh (cached = 0)
        type_data <- type_data[is.na(type_data$cached) | type_data$cached == 0, ]
      }
    } else if (cached_only) {
      return(NULL)  # no cached column ⇒ no distinguishable cache hits
    }

    if (nrow(type_data) > 0) {
      return(round(mean(type_data$duration_sec, na.rm = TRUE), 2))
    }
    return(NULL)
  }, error = function(e) {
    message("[logging.R] Error reading timing log: ", e$message)
    return(NULL)
  })
}

# Rounded fresh/cached time estimates for a report type, for the loading overlay.
# Returns list(fresh, cached) in whole seconds; each falls back to its *_default
# (and stays NULL when neither data nor default is available). `cached` is NULL
# for report types that never cache, which the overlay renders as a single estimate.
report_time_estimates <- function(report_type, fresh_default = NULL, cached_default = NULL) {
  fresh  <- get_average_report_time(report_type, fresh_only = TRUE)
  cached <- get_average_report_time(report_type, cached_only = TRUE)
  list(
    fresh  = if (!is.null(fresh))  round(fresh)  else fresh_default,
    cached = if (!is.null(cached)) round(cached) else cached_default
  )
}

# Create timing status message for user notifications
create_timing_status_message <- function(report_type, action = "Generating") {
  avg_time <- get_average_report_time(report_type)
  
  if (is.null(avg_time)) {
    return(paste(action, report_type, "report... This may take a few moments."))
  } else {
    return(paste(action, report_type, "report... Average time:", avg_time, "seconds."))
  }
}

# Log analysis functions
read_logs <- function(start_date = NULL, end_date = NULL) {
  message("[logging.R] read_logs called with start_date: ", start_date, ", end_date: ", end_date)
  message("[logging.R] cedar_log_dir: ", cedar_log_dir)

  if (!dir.exists(cedar_log_dir)) {
    message("[logging.R] Log directory doesn't exist: ", cedar_log_dir)
    return(data.frame())
  }

  log_files <- list.files(cedar_log_dir, pattern = "cedar_usage_.*\\.log$", full.names = TRUE)
  message("[logging.R] Found ", length(log_files), " log files: ", paste(basename(log_files), collapse = ", "))

  if (length(log_files) == 0) {
    message("[logging.R] No log files found in ", cedar_log_dir)
    return(data.frame())
  }

  # ── PERFORMANCE OPTIMIZATION: Filter files by modification date BEFORE reading ──
  # Only read log files that could potentially contain entries within the date range
  if (!is.null(start_date)) {
    start_datetime <- as.POSIXct(paste(start_date, "00:00:00"), tz = Sys.timezone())

    # Get file modification times
    file_info <- file.info(log_files)
    file_mtimes <- file_info$mtime

    # Only keep files modified on or after start_date
    # (We keep a 1-day buffer in case of timezone issues or late writes)
    buffer_days <- 1
    cutoff_date <- start_datetime - (buffer_days * 86400)  # 86400 seconds = 1 day
    files_to_keep <- log_files[file_mtimes >= cutoff_date]

    files_filtered <- length(log_files) - length(files_to_keep)
    if (files_filtered > 0) {
      message("[logging.R] Filtered out ", files_filtered, " old log files based on modification date")
      message("[logging.R] Reading ", length(files_to_keep), " files modified on or after ", format(cutoff_date, "%Y-%m-%d"))
    }

    log_files <- files_to_keep
  }

  if (length(log_files) == 0) {
    message("[logging.R] No log files match the date range filter")
    return(data.frame())
  }

  # Parse helper shared across all files/lines
  extract_value <- function(field) {
    if (is.null(field)) return(NA)
    if (is.list(field) || is.vector(field)) {
      if (length(field) > 0) return(as.character(field[1]))
      return(NA)
    }
    return(as.character(field))
  }

  # Collect parsed rows into a flat list, then bind once at the end.
  # Avoids the O(n²) cost of rbind()-in-a-loop for large log files.
  all_entries <- list()

  for (log_file in log_files) {
    message("[logging.R] Processing log file: ", log_file)
    if (!file.exists(log_file)) {
      message("[logging.R] Log file doesn't exist: ", log_file)
      next
    }

    lines <- readLines(log_file, warn = FALSE)
    message("[logging.R] Read ", length(lines), " lines from ", basename(log_file))

    file_entries <- lapply(lines, function(line) {
      if (nchar(line) == 0) return(NULL)
      tryCatch({
        log_entry <- jsonlite::fromJSON(line)

        # Handle complex details field
        details_value <- log_entry$details
        if (is.list(details_value) && !is.null(names(details_value))) {
          details_value <- jsonlite::toJSON(details_value, auto_unbox = TRUE)
        } else {
          details_value <- extract_value(details_value)
        }

        data.frame(
          timestamp  = extract_value(log_entry$timestamp),
          level      = extract_value(log_entry$level),
          session_id = extract_value(log_entry$session_id),
          event_type = extract_value(log_entry$event_type),
          details    = as.character(details_value),
          user_agent = extract_value(log_entry$user_agent),
          stringsAsFactors = FALSE
        )
      }, error = function(e) {
        message("[logging.R] Skipping malformed log entry - Error: ", e$message)
        message("[logging.R] Line content: ", line)
        NULL
      })
    })

    valid_entries <- Filter(Negate(is.null), file_entries)
    message("[logging.R] Parsed ", length(valid_entries), " valid entries from ", basename(log_file))
    all_entries <- c(all_entries, valid_entries)
  }

  # Single bind — O(n) instead of O(n²)
  all_logs <- if (length(all_entries) > 0) dplyr::bind_rows(all_entries) else data.frame()
  
  message("[logging.R] Total log entries before filtering: ", nrow(all_logs))
  
  if (nrow(all_logs) > 0) {
    all_logs$timestamp <- as.POSIXct(all_logs$timestamp, tz = Sys.timezone())
    
    # Filter by date range if specified
    if (!is.null(start_date)) {
      before_filter <- nrow(all_logs)
      # Convert start_date to beginning of day in local timezone
      start_datetime <- as.POSIXct(paste(start_date, "00:00:00"), tz = Sys.timezone())
      all_logs <- all_logs[all_logs$timestamp >= start_datetime, ]
      message("[logging.R] After start_date filter (", start_datetime, "): ", nrow(all_logs), " (was ", before_filter, ")")
    }
    if (!is.null(end_date)) {
      before_filter <- nrow(all_logs)
      # Convert end_date to end of day in local timezone
      end_datetime <- as.POSIXct(paste(end_date, "23:59:59"), tz = Sys.timezone())
      all_logs <- all_logs[all_logs$timestamp <= end_datetime, ]
      message("[logging.R] After end_date filter (", end_datetime, "): ", nrow(all_logs), " (was ", before_filter, ")")
    }
  }
  
  message("[logging.R] Returning ", nrow(all_logs), " log entries")
  return(all_logs)
}

# Generate usage statistics
get_usage_stats <- function(start_date = NULL, end_date = NULL) {
  logs <- read_logs(start_date, end_date)
  
  if (nrow(logs) == 0) {
    return(list(message = "No log data available"))
  }
  
  stats <- list()
  
  # Session statistics
  session_logs <- logs[logs$event_type %in% c("session_start", "session_end"), ]
  stats$total_sessions <- length(unique(session_logs$session_id))
  stats$total_session_starts <- nrow(session_logs[session_logs$event_type == "session_start", ])
  
  # Feature usage
  tab_changes <- logs[logs$event_type == "tab_change", ]
  if (nrow(tab_changes) > 0) {
    stats$most_popular_tabs <- head(sort(table(tab_changes$details), decreasing = TRUE), 10)
  }
  
  # Report generation
  reports <- logs[logs$event_type == "report_generated", ]
  if (nrow(reports) > 0) {
    stats$reports_generated <- nrow(reports)
    stats$report_types <- table(reports$details)
  }
  
  # Performance metrics
  performance_logs <- logs[logs$event_type == "performance", ]
  if (nrow(performance_logs) > 0) {
    stats$avg_performance <- aggregate(
      as.numeric(performance_logs$details), 
      by = list(performance_logs$details), 
      FUN = mean
    )
    names(stats$avg_performance) <- c("operation", "avg_duration_seconds")
  }
  
  # Error count
  stats$error_count <- nrow(logs[logs$level == "ERROR", ])
  
  # Date range
  stats$date_range <- list(
    start = min(logs$timestamp),
    end = max(logs$timestamp)
  )
  
  return(stats)
}

# Get human-readable usage overview
# This provides a high-level summary of feature usage that's easy to scan
get_usage_overview <- function(start_date = NULL, end_date = NULL) {
  logs <- read_logs(start_date, end_date)

  if (nrow(logs) == 0) {
    return(list(
      message = "No usage data available for the selected date range",
      summary = data.frame()
    ))
  }

  overview <- list()

  # Total activity
  overview$total_events <- nrow(logs)
  overview$date_range <- list(
    start = min(logs$timestamp),
    end = max(logs$timestamp)
  )
  clean_usage_values <- function(x) {
    if (is.null(x) || length(x) == 0) return(character(0))
    x <- unlist(x, use.names = FALSE, recursive = TRUE)
    if (length(x) == 0) return(character(0))
    x <- as.character(x)
    x[!is.na(x) & nzchar(x)]
  }

  clean_session_ids <- function(x) {
    ids <- clean_usage_values(x)
    ids[!tolower(ids) %in% c("unknown", "null", "na")]
  }

  named_item <- function(x, name) {
    if (is.list(x) && !is.null(names(x)) && name %in% names(x)) return(x[[name]])
    NULL
  }

  session_start_logs <- logs[logs$event_type == "session_start", , drop = FALSE]
  engaged_event_types <- c("tab_change", "report_generated", "file_download")
  engaged_logs <- logs[logs$event_type %in% engaged_event_types, , drop = FALSE]
  overview$session_tokens_seen <- length(unique(clean_session_ids(logs$session_id)))
  overview$sessions_opened <- length(unique(clean_session_ids(session_start_logs$session_id)))
  overview$unique_sessions <- length(unique(clean_session_ids(engaged_logs$session_id)))
  overview$total_events <- nrow(logs)
  overview$user_identity_note <- paste(
    "CEDAR logs browser sessions, not authenticated user identities.",
    "The active-session count includes sessions with tab, report, or download activity."
  )

  first_usage_values <- function(...) {
    for (x in list(...)) {
      values <- clean_usage_values(x)
      if (length(values) > 0) return(values)
    }
    character(0)
  }

  count_df <- function(values, value_col) {
    values <- clean_usage_values(values)
    if (length(values) == 0) {
      out <- data.frame(value = character(), count = integer(), stringsAsFactors = FALSE)
      names(out)[1] <- value_col
      return(out)
    }
    counts <- sort(table(values), decreasing = TRUE)
    out <- data.frame(
      value = names(counts),
      count = as.integer(counts),
      stringsAsFactors = FALSE
    )
    names(out)[1] <- value_col
    rownames(out) <- NULL
    out
  }

  log_dates <- as.Date(logs$timestamp)
  valid_dates <- sort(unique(log_dates[!is.na(log_dates)]))
  if (length(valid_dates) > 0) {
    count_dates <- function(idx) {
      as.integer(table(factor(log_dates[idx], levels = valid_dates)))
    }
    daily_activity <- data.frame(
      date = valid_dates,
      sessions = vapply(valid_dates, function(d) {
        day_engaged <- !is.na(log_dates) & log_dates == d &
          logs$event_type %in% engaged_event_types
        length(unique(clean_session_ids(logs$session_id[day_engaged])))
      }, integer(1)),
      events = count_dates(rep(TRUE, nrow(logs))),
      reports = count_dates(logs$event_type == "report_generated"),
      errors = count_dates(logs$level == "ERROR"),
      stringsAsFactors = FALSE
    )
    overview$daily_activity <- daily_activity
    overview$busiest_day <- daily_activity[which.max(daily_activity$events), , drop = FALSE]
  } else {
    overview$daily_activity <- data.frame(
      date = as.Date(character()),
      sessions = integer(),
      events = integer(),
      reports = integer(),
      errors = integer()
    )
    overview$busiest_day <- NULL
  }

  # Parse tab changes to understand feature usage
  tab_logs <- logs[logs$event_type == "tab_change", ]
  overview$total_tab_views <- nrow(tab_logs)
  if (nrow(tab_logs) > 0) {
    # Extract tab names from details (stored as JSON {"tab":"name"} or plain string)
    tab_names <- sapply(tab_logs$details, function(d) {
      tryCatch({
        obj <- jsonlite::fromJSON(d)
        if (!is.null(obj[["tab"]])) as.character(obj[["tab"]]) else as.character(d)
      }, error = function(e) as.character(d))
    })
    overview$tab_usage <- count_df(tab_names, "tab")
  } else {
    overview$tab_usage <- data.frame(tab = character(), count = integer())
  }

  # Parse report generation logs
  overview$dept_reports <- data.frame(department = character(), count = integer())
  overview$course_reports <- data.frame(course = character(), count = integer())
  overview$report_type_usage <- data.frame(report_type = character(), count = integer())
  overview$campus_usage <- data.frame(campus = character(), count = integer())
  report_logs <- logs[logs$event_type == "report_generated", ]
  if (nrow(report_logs) > 0) {
    # Try to extract department/course info from details (JSON strings)
    dept_reports <- character()
    course_reports <- character()
    report_types <- character()
    campuses <- character()
    enrollment_queries <- 0
    other_reports <- 0

    for (i in 1:nrow(report_logs)) {
      details <- report_logs$details[i]

      # Try to parse as JSON
      tryCatch({
        detail_obj <- jsonlite::fromJSON(details)
        if (!is.list(detail_obj)) detail_obj <- list()

        # Parameters are nested under $parameters by log_report_generation()
        params <- named_item(detail_obj, "parameters") %||% detail_obj
        if (!is.list(params)) params <- list()
        this_report_type <- first_usage_values(
          named_item(detail_obj, "report_type"), named_item(params, "report_type")
        )
        report_types <- c(report_types, if (length(this_report_type) > 0) {
          this_report_type
        } else {
          "unknown_report"
        })

        # Check for department reports
        dept_reports <- c(dept_reports, first_usage_values(
          named_item(params, "department"), named_item(params, "dept"), named_item(params, "dept_code")
        ))

        # Check for course reports (field is "course", not "subject_course")
        course_reports <- c(course_reports, first_usage_values(
          named_item(params, "course"), named_item(params, "subject_course")
        ))

        campuses <- c(campuses, first_usage_values(
          named_item(params, "campus"), named_item(params, "course_campus")
        ))

        # Check for enrollment-related queries
        query_types <- clean_usage_values(named_item(params, "query_type"))
        enrollment_queries <- enrollment_queries +
          sum(grepl("enroll", query_types, ignore.case = TRUE))
      }, error = function(e) {
        # If not JSON, count as other report
        other_reports <<- other_reports + 1
        report_types <<- c(report_types, "unknown_report")
      })
    }

    overview$report_type_usage <- count_df(report_types, "report_type")
    overview$campus_usage <- count_df(campuses, "campus")

    # Department report summary
    if (length(dept_reports) > 0) {
      overview$dept_reports <- count_df(dept_reports, "department")

      # Human-readable summary
      top_depts <- head(overview$dept_reports$department, 5)
      overview$dept_summary <- sprintf("%d department reports (%s%s)",
                                        sum(overview$dept_reports$count),
                                        paste(top_depts, collapse = ", "),
                                        if (nrow(overview$dept_reports) > 5) ", ..." else "")
    }

    # Course report summary
    if (length(course_reports) > 0) {
      overview$course_reports <- count_df(course_reports, "course")

      # Human-readable summary
      top_courses <- head(overview$course_reports$course, 5)
      overview$course_summary <- sprintf("%d course reports (%s%s)",
                                          sum(overview$course_reports$count),
                                          paste(top_courses, collapse = ", "),
                                          if (nrow(overview$course_reports) > 5) ", ..." else "")
    }

    # Enrollment query summary
    if (enrollment_queries > 0) {
      overview$enrollment_summary <- sprintf("%d enrollment queries", enrollment_queries)
    }

    # Other reports
    if (other_reports > 0) {
      overview$other_reports_count <- other_reports
    }

    overview$total_reports <- nrow(report_logs)
  } else {
    overview$total_reports <- 0
  }

  download_logs <- logs[logs$event_type == "file_download", ]
  overview$total_downloads <- nrow(download_logs)

  # Error summary
  error_logs <- logs[logs$level == "ERROR", ]
  if (nrow(error_logs) > 0) {
    overview$errors_count <- nrow(error_logs)
    overview$errors_summary <- sprintf("%d errors logged", nrow(error_logs))
  } else {
    overview$errors_count <- 0
  }

  # Create a high-level summary data frame for display
  summary_items <- character()

  if (overview$unique_sessions > 0) {
    session_word <- if (identical(overview$unique_sessions, 1L)) "session" else "sessions"
    summary_items <- c(summary_items, sprintf("%d active %s", overview$unique_sessions, session_word))
  }

  if (!is.null(overview$dept_summary)) {
    summary_items <- c(summary_items, overview$dept_summary)
  }

  if (!is.null(overview$course_summary)) {
    summary_items <- c(summary_items, overview$course_summary)
  }

  if (!is.null(overview$enrollment_summary)) {
    summary_items <- c(summary_items, overview$enrollment_summary)
  }

  if (overview$errors_count > 0) {
    summary_items <- c(summary_items, overview$errors_summary)
  }

  overview$summary_text <- summary_items

  return(overview)
}

# Print usage summary
print_usage_summary <- function(start_date = NULL, end_date = NULL) {
  stats <- get_usage_stats(start_date, end_date)
  
  if ("message" %in% names(stats)) {
    cat(stats$message, "\n")
    return()
  }
  
  cat("CEDAR Usage Statistics\n")
  cat("======================\n")
  cat("Date Range:", format(stats$date_range$start, "%Y-%m-%d"), "to", format(stats$date_range$end, "%Y-%m-%d"), "\n")
  cat("Total Sessions:", stats$total_sessions, "\n")
  cat("Session Starts:", stats$total_session_starts, "\n")
  
  if ("reports_generated" %in% names(stats)) {
    cat("Reports Generated:", stats$reports_generated, "\n")
  }
  
  if ("most_popular_tabs" %in% names(stats)) {
    cat("\nMost Popular Tabs:\n")
    for (i in 1:min(5, length(stats$most_popular_tabs))) {
      cat("  ", names(stats$most_popular_tabs)[i], ":", stats$most_popular_tabs[i], "\n")
    }
  }
  
  cat("Errors:", stats$error_count, "\n")
}

message("[logging.R] Logging functions loaded")
