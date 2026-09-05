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

  tryCatch(
    with_timing_log_lock(
      report_timing_log_file,
      function() ensure_report_timing_schema(report_timing_log_file)
    ),
    error = function(e) message("[logging.R] Could not migrate report timing log: ",
                               e$message)
  )
  tryCatch(
    with_timing_log_lock(
      client_render_timing_log_file,
      function() ensure_client_timing_schema(client_render_timing_log_file)
    ),
    error = function(e) message("[logging.R] Could not migrate client timing log: ",
                               e$message)
  )
  
  # Clean up old log files
  cleanup_old_logs()
  
  message("[logging.R] Logging initialized. Log file: ", cedar_log_file)
}

# Archive closed usage files; never delete history or overwrite an archive.
cleanup_old_logs <- function(log_dir = cedar_log_dir,
                             retention_days = cedar_log_retention_days,
                             today = Sys.Date()) {
  if (!dir.exists(log_dir)) return(invisible(character(0)))
  stopifnot(length(retention_days) == 1L, is.finite(retention_days), retention_days > 0)
  log_files <- list.files(log_dir, pattern = "^cedar_usage_.*\\.log$", full.names = TRUE)
  cutoff_date <- today - retention_days
  archived <- character(0)
  for (log_file in log_files) {
    file_date <- as.Date(file.mtime(log_file))
    if (!is.na(file_date) && file_date < cutoff_date &&
        basename(log_file) != basename(usage_log_path(log_dir, today))) {
      archive_dir <- file.path(log_dir, "archive")
      dir.create(archive_dir, showWarnings = FALSE)
      destination <- file.path(archive_dir, basename(log_file))
      if (file.exists(destination) || !file.rename(log_file, destination)) {
        warning("[logging.R] Could not archive without overwriting: ", basename(log_file))
      } else {
        archived <- c(archived, destination)
      }
    }
  }
  if (length(archived)) message("[logging.R] Archived ", length(archived), " usage log file(s); history retained.")
  invisible(archived)
}

# Core logging function
write_log <- function(level, event_type, details = NULL, session_id = NULL, user_agent = NULL) {
  if (!cedar_logging_enabled) return()
  
  # Check log level
  log_levels <- c("DEBUG" = 1, "INFO" = 2, "WARN" = 3, "ERROR" = 4)
  if (log_levels[level] < log_levels[cedar_log_level]) return()
  
  event_time <- Sys.time()
  timestamp <- format(event_time, "%Y-%m-%d %H:%M:%S")
  
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
    # Resolve on every write so long-lived sessions rotate at midnight too.
    write(log_line, file = usage_log_path(cedar_log_dir, event_time), append = TRUE)
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
client_render_timing_log_file <- file.path(cedar_data_dir, "client_render_timing.csv")

REPORT_TIMING_COLUMNS <- c(
  "timestamp", "report_type", "duration_sec", "cached", "report_params",
  "operation_id", "session_id", "cpu_user_sec", "cpu_system_sec",
  "cpu_total_sec", "rss_start_mb", "rss_end_mb", "rss_delta_mb",
  "result_size_mb", "connected_sessions", "success", "error_class"
)

CLIENT_TIMING_COLUMNS <- c(
  "timestamp", "report_type", "overlay_id", "compute_sec", "total_sec",
  "post_compute_sec", "payload_bytes", "output_count", "cached",
  "viewport_width", "viewport_height", "operation_id", "session_id",
  "queue_delivery_sec", "browser_settle_sec", "connected_sessions"
)

# Process-local state supplies correlation IDs and lightweight concurrency
# context. Shiny executes ordinary reactive work in one R process, so this does
# not attempt to count simultaneous CPU work; connected sessions are recorded
# to show whether slow runs occurred while the process was serving more users.
.cedar_performance_state <- local({
  state <- new.env(parent = emptyenv())
  state$operation_counter <- 0L
  state$session_ids <- new.env(hash = TRUE, parent = emptyenv())
  state
})

performance_register_session <- function(session_id) {
  if (!is.null(session_id) && length(session_id) == 1L &&
      !is.na(session_id) && nzchar(as.character(session_id))) {
    assign(as.character(session_id), TRUE,
           envir = .cedar_performance_state$session_ids)
  }
  invisible(NULL)
}

performance_unregister_session <- function(session_id) {
  key <- if (is.null(session_id) || length(session_id) != 1L) "" else as.character(session_id)
  if (nzchar(key) && exists(key, envir = .cedar_performance_state$session_ids,
                            inherits = FALSE)) {
    rm(list = key, envir = .cedar_performance_state$session_ids)
  }
  invisible(NULL)
}

cedar_connected_session_count <- function() {
  length(ls(envir = .cedar_performance_state$session_ids, all.names = TRUE))
}

next_performance_operation_id <- function() {
  .cedar_performance_state$operation_counter <-
    .cedar_performance_state$operation_counter + 1L
  paste(Sys.getpid(), .cedar_performance_state$operation_counter,
        format(Sys.time(), "%Y%m%d%H%M%OS6"), sep = "-")
}

current_performance_session_id <- function(session = NULL) {
  if (is.null(session) && requireNamespace("shiny", quietly = TRUE)) {
    session <- tryCatch(shiny::getDefaultReactiveDomain(), error = function(e) NULL)
  }
  token <- tryCatch(session$token, error = function(e) NULL)
  if (is.null(token) || length(token) != 1L || is.na(token) || !nzchar(token)) {
    return(NA_character_)
  }
  as.character(token)
}

# RSS is the worker process footprint, not an allocation profiler. It is cheap
# enough for production and, paired with result_size_mb, identifies reports that
# retain large payloads without forcing garbage collection or profiling every
# allocation.
process_rss_mb <- function() {
  if (!requireNamespace("ps", quietly = TRUE)) return(NA_real_)
  tryCatch(
    as.numeric(ps::ps_memory_info(ps::ps_handle())[["rss"]]) / 1024^2,
    error = function(e) NA_real_
  )
}

process_cpu_seconds <- function() {
  timing <- proc.time()
  c(
    user = unname(timing[["user.self"]] + timing[["user.child"]]),
    system = unname(timing[["sys.self"]] + timing[["sys.child"]])
  )
}

# Directory creation is atomic across processes. This small lock prevents two
# Shiny workers from migrating or appending the same CSV at once. A stale lock
# left by a killed worker is removed after 30 seconds.
with_timing_log_lock <- function(path, action, timeout_sec = 2) {
  lock_dir <- paste0(path, ".lock")
  dir.create(dirname(lock_dir), recursive = TRUE, showWarnings = FALSE)
  deadline <- Sys.time() + timeout_sec

  repeat {
    if (isTRUE(dir.create(lock_dir, showWarnings = FALSE))) break

    lock_info <- suppressWarnings(file.info(lock_dir))
    if (nrow(lock_info) == 1L && !is.na(lock_info$mtime) &&
        as.numeric(difftime(Sys.time(), lock_info$mtime, units = "secs")) > 30) {
      unlink(lock_dir, recursive = TRUE)
      next
    }
    if (Sys.time() >= deadline) {
      stop("Timed out waiting for timing-log lock: ", lock_dir, call. = FALSE)
    }
    Sys.sleep(0.01)
  }

  on.exit(unlink(lock_dir, recursive = TRUE), add = TRUE)
  action()
}

empty_report_timings <- function() {
  data.frame(
    timestamp = character(),
    report_type = character(),
    duration_sec = numeric(),
    cached = integer(),
    report_params = character(),
    operation_id = character(),
    session_id = character(),
    cpu_user_sec = numeric(),
    cpu_system_sec = numeric(),
    cpu_total_sec = numeric(),
    rss_start_mb = numeric(),
    rss_end_mb = numeric(),
    rss_delta_mb = numeric(),
    result_size_mb = numeric(),
    connected_sessions = integer(),
    success = integer(),
    error_class = character(),
    stringsAsFactors = FALSE
  )
}

empty_client_timings <- function() {
  data.frame(
    timestamp = character(), report_type = character(), overlay_id = character(),
    compute_sec = numeric(), total_sec = numeric(), post_compute_sec = numeric(),
    payload_bytes = numeric(), output_count = numeric(), cached = integer(),
    viewport_width = numeric(), viewport_height = numeric(),
    operation_id = character(), session_id = character(),
    queue_delivery_sec = numeric(), browser_settle_sec = numeric(),
    connected_sessions = integer(), stringsAsFactors = FALSE
  )
}

align_timing_columns <- function(rows, template, columns) {
  n <- nrow(rows)
  for (name in setdiff(columns, names(rows))) {
    prototype <- template[[name]]
    rows[[name]] <- if (is.integer(prototype)) {
      rep(NA_integer_, n)
    } else if (is.numeric(prototype)) {
      rep(NA_real_, n)
    } else {
      rep(NA_character_, n)
    }
  }
  rows[, columns, drop = FALSE]
}

normalize_report_timings <- function(rows) {
  align_timing_columns(rows, empty_report_timings(), REPORT_TIMING_COLUMNS)
}

normalize_client_timings <- function(rows) {
  align_timing_columns(rows, empty_client_timings(), CLIENT_TIMING_COLUMNS)
}

# Decode one character field written by write.table(). Older timing files used
# qmethod = "escape", while the canonical writer below uses RFC-style doubled
# quotes. Supporting both lets CEDAR recover the historical rows before it
# rewrites the file with the current schema.
decode_report_timing_field <- function(value) {
  if (length(value) == 0L || is.na(value) || identical(value, "NA")) {
    return(NA_character_)
  }
  if (nchar(value) >= 2L && startsWith(value, "\"") && endsWith(value, "\"")) {
    value <- substr(value, 2L, nchar(value) - 1L)
    value <- gsub("\"\"", "\"", value, fixed = TRUE)
    value <- gsub("\\\"", "\"", value, fixed = TRUE)
  }
  value
}

# Parse report timing rows by their stable scalar prefix. This deliberately
# does not ask read.csv() to interpret legacy report_params: embedded JSON
# commas and backslash-escaped quotes made those files invalid RFC CSV.
parse_report_timing_line <- function(line) {
  match <- regexec(
    '^"([^"]*)","([^"]*)",([^,]+),(.*)$', line, perl = TRUE
  )
  fields <- regmatches(line, match)[[1]]
  if (length(fields) != 5L) return(NULL)

  tail <- fields[[5]]
  cached_match <- regexec('^([01]|NA),(.*)$', tail, perl = TRUE)
  cached_fields <- regmatches(tail, cached_match)[[1]]
  if (length(cached_fields) == 3L) {
    cached <- suppressWarnings(as.integer(cached_fields[[2]]))
    params <- cached_fields[[3]]
  } else {
    cached <- NA_integer_
    params <- tail
  }

  duration <- suppressWarnings(as.numeric(fields[[4]]))
  if (!is.finite(duration)) return(NULL)

  normalize_report_timings(data.frame(
    timestamp = fields[[2]],
    report_type = fields[[3]],
    duration_sec = duration,
    cached = cached,
    report_params = decode_report_timing_field(params),
    stringsAsFactors = FALSE
  ))
}

# Read both the original four-column timing file and the mixed file produced
# after the cached flag was introduced. Invalid physical lines are skipped and
# reported rather than shifting columns and manufacturing extra observations.
read_report_timings <- function(path = report_timing_log_file) {
  if (!file.exists(path)) return(empty_report_timings())

  lines <- readLines(path, warn = FALSE)
  if (length(lines) <= 1L) return(empty_report_timings())

  canonical_header <- paste(sprintf('"%s"', REPORT_TIMING_COLUMNS), collapse = ",")
  if (identical(lines[[1]], canonical_header)) {
    return(normalize_report_timings(
      utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    ))
  }

  parsed <- lapply(lines[-1L], parse_report_timing_line)
  valid <- !vapply(parsed, is.null, logical(1))
  if (any(!valid)) {
    message("[logging.R] Skipped ", sum(!valid),
            " malformed report timing row(s) in ", path)
  }
  if (!any(valid)) return(empty_report_timings())

  result <- do.call(rbind, parsed[valid])
  rownames(result) <- NULL
  result
}

write_report_timings <- function(timing_rows, path = report_timing_log_file) {
  timing_rows <- normalize_report_timings(timing_rows)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  on.exit(unlink(tmp), add = TRUE)

  write.table(
    timing_rows, tmp, sep = ",", row.names = FALSE, col.names = TRUE,
    append = FALSE, qmethod = "double", na = "NA"
  )
  if (!isTRUE(file.rename(tmp, path))) {
    stop("[logging.R] Could not replace report timing log: ", path,
         call. = FALSE)
  }
  invisible(TRUE)
}

# Upgrade a legacy/mixed timing file once. Keep the original beside it so an
# operator can recover any line the tolerant parser could not understand.
ensure_report_timing_schema <- function(path = report_timing_log_file) {
  if (!file.exists(path)) return(invisible(FALSE))

  header <- readLines(path, n = 1L, warn = FALSE)
  canonical_header <- paste(sprintf('"%s"', REPORT_TIMING_COLUMNS), collapse = ",")
  if (length(header) == 1L && identical(header, canonical_header)) {
    return(invisible(FALSE))
  }

  timing_rows <- read_report_timings(path)
  backup <- paste0(path, ".legacy")
  if (!file.exists(backup)) {
    file.copy(path, backup, overwrite = FALSE)
  }
  write_report_timings(timing_rows, path)
  message("[logging.R] Migrated report timing log to schema: ",
          paste(REPORT_TIMING_COLUMNS, collapse = ", "))
  invisible(TRUE)
}

#' Reset recorded report timing observations
#'
#' Removes the timing-history CSV used to estimate fresh-compute and cache-hit
#' durations. The next completed report recreates the file with a header, so
#' callers immediately fall back to their configured defaults and then begin
#' learning new estimates from subsequent runs.
#'
#' @param path Timing-history CSV. Defaults to the active CEDAR timing log.
#' @return Integer number of timing observations removed.
reset_report_timings <- function(path = report_timing_log_file) {
  if (!file.exists(path)) return(0L)

  n_observations <- with_timing_log_lock(path, function() {
    if (!file.exists(path)) return(0L)
    n <- max(length(readLines(path, warn = FALSE)) - 1L, 0L)
    if (!isTRUE(file.remove(path))) {
      stop("[logging.R] Could not remove report timing history: ", path,
           call. = FALSE)
    }
    n
  })

  message("[logging.R] Reset report timing history (", n_observations,
          " observations removed from ", path, ")")
  as.integer(n_observations)
}

read_client_timings <- function(path = client_render_timing_log_file) {
  if (!file.exists(path)) return(empty_client_timings())
  rows <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(rows) == 0L) return(empty_client_timings())
  normalize_client_timings(rows)
}

write_client_timings <- function(timing_rows,
                                 path = client_render_timing_log_file) {
  timing_rows <- normalize_client_timings(timing_rows)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  on.exit(unlink(tmp), add = TRUE)
  write.table(
    timing_rows, tmp, sep = ",", row.names = FALSE, col.names = TRUE,
    append = FALSE, qmethod = "double", na = "NA"
  )
  if (!isTRUE(file.rename(tmp, path))) {
    stop("[logging.R] Could not replace client timing log: ", path,
         call. = FALSE)
  }
  invisible(TRUE)
}

ensure_client_timing_schema <- function(path = client_render_timing_log_file) {
  if (!file.exists(path)) return(invisible(FALSE))

  header <- readLines(path, n = 1L, warn = FALSE)
  canonical_header <- paste(sprintf('"%s"', CLIENT_TIMING_COLUMNS), collapse = ",")
  if (length(header) == 1L && identical(header, canonical_header)) {
    return(invisible(FALSE))
  }

  timing_rows <- read_client_timings(path)
  backup <- paste0(path, ".legacy")
  if (!file.exists(backup)) file.copy(path, backup, overwrite = FALSE)
  write_client_timings(timing_rows, path)
  message("[logging.R] Migrated client timing log to schema: ",
          paste(CLIENT_TIMING_COLUMNS, collapse = ", "))
  invisible(TRUE)
}

#' Record the user-visible portion of a report load
#'
#' The browser starts this clock when a report is requested and stops it after
#' Shiny is idle and the browser has completed two paint frames. The legacy
#' `post_compute` field is all non-compute time. New rows split that into
#' `queue_delivery_sec` (event-loop waiting plus delivery up to the completion
#' message) and `browser_settle_sec` (the remaining output/paint work). Payload
#' bytes approximate the JSON values delivered to Shiny outputs.
#'
#' @param timing Named list sent by cedar_loading_overlay().
#' @param path Client timing CSV.
#' @return Invisibly, TRUE when a row was written and FALSE for invalid input.
log_client_render_timing <- function(timing, session_id = NULL,
                                     connected_sessions = NULL,
                                     path = client_render_timing_log_file) {
  if (!is.list(timing)) return(invisible(FALSE))

  scalar_text <- function(x, fallback = "unknown") {
    if (is.null(x) || length(x) != 1L || is.na(x)) return(fallback)
    value <- substr(as.character(x), 1L, 100L)
    value <- gsub("[^A-Za-z0-9_.:-]", "_", value)
    if (nzchar(value)) value else fallback
  }
  scalar_number <- function(x, upper = Inf) {
    if (is.null(x) || length(x) != 1L) return(NA_real_)
    value <- suppressWarnings(as.numeric(x))
    if (!is.finite(value) || value < 0 || value > upper) NA_real_ else value
  }
  scalar_flag <- function(x) {
    if (is.null(x) || length(x) != 1L || is.na(x)) return(NA_integer_)
    as.integer(isTRUE(x) || identical(x, 1L) || identical(x, 1) || identical(x, "true"))
  }

  total_sec <- scalar_number(timing$total_sec, upper = 7200)
  if (is.na(total_sec)) return(invisible(FALSE))

  timing_row <- data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    report_type = scalar_text(timing$report_type),
    overlay_id = scalar_text(timing$overlay_id),
    compute_sec = scalar_number(timing$compute_sec, upper = 7200),
    total_sec = total_sec,
    post_compute_sec = scalar_number(timing$post_compute_sec, upper = 7200),
    payload_bytes = scalar_number(timing$payload_bytes, upper = 2^31),
    output_count = scalar_number(timing$output_count, upper = 10000),
    cached = scalar_flag(timing$cached),
    viewport_width = scalar_number(timing$viewport_width, upper = 20000),
    viewport_height = scalar_number(timing$viewport_height, upper = 20000),
    operation_id = scalar_text(timing$operation_id, fallback = NA_character_),
    session_id = scalar_text(session_id, fallback = NA_character_),
    queue_delivery_sec = scalar_number(timing$queue_delivery_sec, upper = 7200),
    browser_settle_sec = scalar_number(timing$browser_settle_sec, upper = 7200),
    connected_sessions = scalar_number(connected_sessions, upper = 100000),
    stringsAsFactors = FALSE
  )

  with_timing_log_lock(path, function() {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    ensure_client_timing_schema(path)
    write.table(
      normalize_client_timings(timing_row), path, sep = ",", row.names = FALSE,
      col.names = !file.exists(path), append = file.exists(path),
      qmethod = "double", na = "NA"
    )
  })
  invisible(TRUE)
}

#' Reset recorded browser-visible report timings
#'
#' @param path Client timing CSV.
#' @return Integer number of observations removed.
reset_client_render_timings <- function(path = client_render_timing_log_file) {
  if (!file.exists(path)) return(0L)

  n_observations <- with_timing_log_lock(path, function() {
    if (!file.exists(path)) return(0L)
    n <- max(length(readLines(path, warn = FALSE)) - 1L, 0L)
    if (!isTRUE(file.remove(path))) {
      stop("[logging.R] Could not remove client timing history: ", path,
           call. = FALSE)
    }
    n
  })

  message("[logging.R] Reset client timing history (", n_observations,
          " observations removed from ", path, ")")
  as.integer(n_observations)
}

#' Summarize end-to-end and server resource timings for Admin
#'
#' Medians describe a normal run; the 90th percentile exposes the slow tail
#' that matters during concurrent use. RSS is the whole R worker's resident
#' memory, while result size is the retained R object returned by the report.
#'
#' @return One row per report type and cache path, or an empty data frame.
get_performance_timing_summary <- function(
    report_path = report_timing_log_file,
    client_path = client_render_timing_log_file) {
  empty_summary <- data.frame(
    report_type = character(), cache_path = character(), browser_runs = integer(),
    server_runs = integer(), failures = integer(), median_total_sec = numeric(),
    p90_total_sec = numeric(), median_compute_sec = numeric(),
    p90_compute_sec = numeric(), median_queue_delivery_sec = numeric(),
    median_browser_settle_sec = numeric(), median_cpu_sec = numeric(),
    median_rss_delta_mb = numeric(), p90_result_size_mb = numeric(),
    max_worker_rss_mb = numeric(), avg_payload_mb = numeric(),
    max_payload_mb = numeric(), connected_sessions = numeric(),
    last_observed = character(), stringsAsFactors = FALSE
  )

  clean_number <- function(x, fun, ...) {
    x <- x[is.finite(x)]
    if (length(x) == 0L) return(NA_real_)
    as.numeric(fun(x, ...))
  }
  q90 <- function(x) clean_number(x, stats::quantile, probs = 0.90,
                                  names = FALSE, type = 7)
  med <- function(x) clean_number(x, stats::median)
  mx <- function(x) clean_number(x, max)
  avg <- function(x) clean_number(x, mean)
  cache_label <- function(x) ifelse(!is.na(x) & x == 1L, "Cached", "Fresh / uncached")

  tryCatch({
    client <- read_client_timings(client_path)
    server <- read_report_timings(report_path)

    client_summary <- if (nrow(client) == 0L) {
      NULL
    } else {
      client %>%
        dplyr::mutate(cache_path = cache_label(cached)) %>%
        dplyr::group_by(report_type, cache_path) %>%
        dplyr::summarise(
          browser_runs = dplyr::n(),
          median_total_sec = med(total_sec),
          p90_total_sec = q90(total_sec),
          median_compute_sec = med(compute_sec),
          p90_compute_sec = q90(compute_sec),
          median_queue_delivery_sec = med(queue_delivery_sec),
          median_browser_settle_sec = med(browser_settle_sec),
          avg_payload_mb = avg(payload_bytes) / 1024^2,
          max_payload_mb = mx(payload_bytes) / 1024^2,
          connected_sessions_client = mx(connected_sessions),
          last_client = max(timestamp, na.rm = TRUE),
          .groups = "drop"
        )
    }

    server_summary <- if (nrow(server) == 0L) {
      NULL
    } else {
      server %>%
        dplyr::mutate(cache_path = cache_label(cached)) %>%
        dplyr::group_by(report_type, cache_path) %>%
        dplyr::summarise(
          server_runs = dplyr::n(),
          failures = sum(!is.na(success) & success == 0L),
          median_cpu_sec = med(cpu_total_sec),
          median_rss_delta_mb = med(rss_delta_mb),
          p90_result_size_mb = q90(result_size_mb),
          max_worker_rss_mb = mx(rss_end_mb),
          connected_sessions_server = mx(connected_sessions),
          last_server = max(timestamp, na.rm = TRUE),
          .groups = "drop"
        )
    }

    if (is.null(client_summary) && is.null(server_summary)) return(empty_summary)
    if (is.null(client_summary)) {
      combined <- server_summary
    } else if (is.null(server_summary)) {
      combined <- client_summary
    } else {
      combined <- dplyr::full_join(
        client_summary, server_summary,
        by = c("report_type", "cache_path")
      )
    }

    required <- setdiff(names(empty_summary), c("connected_sessions", "last_observed"))
    for (name in setdiff(required, names(combined))) combined[[name]] <- NA
    if (!"connected_sessions_client" %in% names(combined)) {
      combined$connected_sessions_client <- NA_real_
    }
    if (!"connected_sessions_server" %in% names(combined)) {
      combined$connected_sessions_server <- NA_real_
    }
    if (!"last_client" %in% names(combined)) combined$last_client <- NA_character_
    if (!"last_server" %in% names(combined)) combined$last_server <- NA_character_

    combined %>%
      dplyr::mutate(
        connected_sessions = pmax(connected_sessions_client,
                                  connected_sessions_server, na.rm = TRUE),
        connected_sessions = dplyr::if_else(
          is.infinite(connected_sessions), NA_real_, connected_sessions
        ),
        last_observed = pmax(last_client, last_server, na.rm = TRUE),
        last_observed = dplyr::if_else(
          is.na(last_observed) | last_observed == "-Inf", NA_character_, last_observed
        ),
        dplyr::across(
          where(is.numeric),
          ~ dplyr::if_else(is.nan(.x) | is.infinite(.x), NA_real_, round(.x, 2))
        )
      ) %>%
      dplyr::select(dplyr::all_of(names(empty_summary))) %>%
      dplyr::arrange(dplyr::desc(p90_total_sec),
                     dplyr::desc(p90_compute_sec),
                     dplyr::desc(server_runs)) %>%
      as.data.frame(stringsAsFactors = FALSE)
  }, error = function(e) {
    message("[logging.R] Error building performance summary: ", e$message)
    empty_summary
  })
}

# Backward-compatible name used by older callers and scripts.
get_client_render_timing_summary <- function(path = client_render_timing_log_file) {
  get_performance_timing_summary(client_path = path)
}

# Start a timed report operation and return timing context. Session is normally
# discovered from the active Shiny reactive domain, but may be supplied by tests
# or non-reactive callers.
start_report_timer <- function(report_type, report_params = NULL, session = NULL) {
  cpu <- process_cpu_seconds()
  timing_context <- list(
    report_type = report_type,
    report_params = report_params,
    operation_id = next_performance_operation_id(),
    session_id = current_performance_session_id(session),
    connected_sessions = cedar_connected_session_count(),
    start_time = Sys.time(),
    start_cpu_user = cpu[["user"]],
    start_cpu_system = cpu[["system"]],
    rss_start_mb = process_rss_mb()
  )
  
  return(timing_context)
}

# End timer and log the results.
# cached = TRUE marks this run as a cache hit so averages for status messages
# exclude it — cache hits are fast enough to skew estimates for fresh runs.
end_report_timer <- function(timing_context, cached = FALSE, result,
                             success = TRUE, error = NULL) {
  end_time <- Sys.time()
  duration_sec <- as.numeric(difftime(end_time, timing_context$start_time, units = "secs"))
  cpu <- process_cpu_seconds()
  cpu_user_sec <- max(cpu[["user"]] - timing_context$start_cpu_user, 0)
  cpu_system_sec <- max(cpu[["system"]] - timing_context$start_cpu_system, 0)
  rss_end_mb <- process_rss_mb()
  result_size_mb <- if (missing(result)) {
    NA_real_
  } else {
    tryCatch(as.numeric(utils::object.size(result)) / 1024^2,
             error = function(e) NA_real_)
  }
  success <- isTRUE(success) && is.null(error)
  error_class <- if (is.null(error)) NA_character_ else class(error)[[1]]

  # Create log entry
  timing_row <- data.frame(
    timestamp = format(timing_context$start_time, "%Y-%m-%d %H:%M:%S"),
    report_type = timing_context$report_type,
    duration_sec = duration_sec,
    cached = if (is.null(cached)) NA_integer_ else as.integer(isTRUE(cached)),
    report_params = if(is.null(timing_context$report_params)) NA else jsonlite::toJSON(json_ready(timing_context$report_params), auto_unbox = TRUE),
    operation_id = timing_context$operation_id,
    session_id = timing_context$session_id,
    cpu_user_sec = cpu_user_sec,
    cpu_system_sec = cpu_system_sec,
    cpu_total_sec = cpu_user_sec + cpu_system_sec,
    rss_start_mb = timing_context$rss_start_mb,
    rss_end_mb = rss_end_mb,
    rss_delta_mb = rss_end_mb - timing_context$rss_start_mb,
    result_size_mb = result_size_mb,
    connected_sessions = timing_context$connected_sessions,
    success = as.integer(success),
    error_class = error_class,
    stringsAsFactors = FALSE
  )
  
  # Upgrade legacy/mixed logs before appending. qmethod = "double" keeps the
  # JSON parameter field valid CSV for read.csv() and other standard readers.
  tryCatch({
    with_timing_log_lock(report_timing_log_file, function() {
      dir.create(dirname(report_timing_log_file), recursive = TRUE,
                 showWarnings = FALSE)
      ensure_report_timing_schema(report_timing_log_file)
      write.table(
        normalize_report_timings(timing_row), report_timing_log_file,
        sep = ",", row.names = FALSE,
        col.names = !file.exists(report_timing_log_file),
        append = file.exists(report_timing_log_file), qmethod = "double", na = "NA"
      )
    })
  }, error = function(e) {
    message("[logging.R] Could not write report timing: ", e$message)
  })
  
  message(sprintf("[logging.R] %s completed in %.2f seconds (logged to %s)", 
                  timing_context$report_type, duration_sec, report_timing_log_file))
  
  attr(duration_sec, "operation_id") <- timing_context$operation_id
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
    log_data <- read_report_timings(report_timing_log_file)
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

# Robust fresh/cached estimates for the loading overlay. Recent browser-visible
# totals take precedence over calculation-only timings. The median-to-P90 range
# communicates both a typical run and the slow tail; static defaults are used
# only until observations exist.
report_time_estimates <- function(report_type, fresh_default = NULL, cached_default = NULL) {
  client_history <- tryCatch(
    read_client_timings(), error = function(e) empty_client_timings()
  )
  server_history <- NULL
  load_server_history <- function() {
    if (is.null(server_history)) {
      server_history <<- tryCatch(
        read_report_timings(), error = function(e) empty_report_timings()
      )
    }
    server_history
  }

  distribution <- function(cached, default) {
    keep <- client_history$report_type == report_type & if (cached) {
      !is.na(client_history$cached) & client_history$cached == 1L
    } else {
      is.na(client_history$cached) | client_history$cached == 0L
    }
    values <- client_history$total_sec[keep]
    values <- tail(values[is.finite(values) & values >= 0], 100L)
    source <- "browser_total"

    # Three end-to-end observations are enough to replace a static default.
    # Until then, use the more plentiful server history, clearly retaining its
    # calculation-only meaning in the source field returned for diagnostics.
    if (length(values) < 3L) {
      server <- load_server_history()
      keep <- server$report_type == report_type & if (cached) {
        !is.na(server$cached) & server$cached == 1L
      } else {
        is.na(server$cached) | server$cached == 0L
      }
      values <- tail(server$duration_sec[keep], 100L)
      values <- values[is.finite(values) & values >= 0]
      source <- "server_compute"
    }

    if (length(values) == 0L) {
      if (is.null(default)) return(NULL)
      value <- max(1L, as.integer(round(default)))
      return(list(estimate = value, lower = value, upper = value,
                  runs = 0L, source = "default"))
    }

    lower <- max(1L, as.integer(round(stats::median(values))))
    upper <- max(lower, as.integer(ceiling(stats::quantile(
      values, probs = 0.90, names = FALSE, type = 7
    ))))
    list(estimate = lower, lower = lower, upper = upper,
         runs = length(values), source = source)
  }

  fresh_range <- distribution(FALSE, fresh_default)
  cached_range <- distribution(TRUE, cached_default)
  list(
    fresh  = if (is.null(fresh_range)) NULL else fresh_range$estimate,
    cached = if (is.null(cached_range)) NULL else cached_range$estimate,
    fresh_range = fresh_range,
    cached_range = cached_range
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
read_logs <- function(start_date = NULL, end_date = NULL, log_dir = cedar_log_dir) {
  cedar_debug("[logging.R] read_logs called with start_date: ", start_date, ", end_date: ", end_date)
  cedar_debug("[logging.R] cedar_log_dir: ", log_dir)

  if (!dir.exists(log_dir)) {
    message("[logging.R] Log directory doesn't exist: ", log_dir)
    return(data.frame())
  }

  log_files <- usage_log_files(log_dir, start_date, end_date)
  if (length(log_files) == 0L) return(data.frame())
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
    cedar_debug("[logging.R] Processing log file: ", log_file)
    if (!file.exists(log_file)) {
      message("[logging.R] Log file doesn't exist: ", log_file)
      next
    }

    lines <- readLines(log_file, warn = FALSE)
    lines <- filter_usage_log_lines(lines, start_date, end_date)
    cedar_debug("[logging.R] Read ", length(lines), " lines from ", basename(log_file))

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
        NULL
      })
    })

    valid_entries <- Filter(Negate(is.null), file_entries)
    cedar_debug("[logging.R] Parsed ", length(valid_entries), " valid entries from ", basename(log_file))
    all_entries <- c(all_entries, valid_entries)
  }

  # Single bind — O(n) instead of O(n²)
  all_logs <- if (length(all_entries) > 0) dplyr::bind_rows(all_entries) else data.frame()
  
  cedar_debug("[logging.R] Total log entries before filtering: ", nrow(all_logs))
  
  if (nrow(all_logs) > 0) {
    all_logs$timestamp <- as.POSIXct(all_logs$timestamp, tz = Sys.timezone())
    
    # Filter by date range if specified
    if (!is.null(start_date)) {
      before_filter <- nrow(all_logs)
      # Convert start_date to beginning of day in local timezone
      start_datetime <- as.POSIXct(paste(start_date, "00:00:00"), tz = Sys.timezone())
      all_logs <- all_logs[!is.na(all_logs$timestamp) & all_logs$timestamp >= start_datetime, ]
      cedar_debug("[logging.R] After start_date filter (", start_datetime, "): ", nrow(all_logs), " (was ", before_filter, ")")
    }
    if (!is.null(end_date)) {
      before_filter <- nrow(all_logs)
      # Convert end_date to end of day in local timezone
      end_datetime <- as.POSIXct(paste(end_date, "23:59:59"), tz = Sys.timezone())
      all_logs <- all_logs[!is.na(all_logs$timestamp) & all_logs$timestamp <= end_datetime, ]
      cedar_debug("[logging.R] After end_date filter (", end_datetime, "): ", nrow(all_logs), " (was ", before_filter, ")")
    }
  }
  
  cedar_debug("[logging.R] Returning ", nrow(all_logs), " log entries")
  return(all_logs)
}

# Generate usage statistics
get_usage_stats <- function(start_date = NULL, end_date = NULL,
                            logs = read_logs(start_date, end_date)) {
  
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
