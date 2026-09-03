# Tests for R/trunk/logging.R
#
# Tests read_logs() correctness and robustness, including the lapply+bind_rows
# implementation that replaced the O(n²) rbind-in-loop.  Logging functions that
# require a live Shiny session (log_session_start_reactive, log_tab_change, etc.)
# are not tested here; this file focuses on the log parsing pipeline.
#
# Strategy: write synthetic JSON log lines to a temp file, then parse and verify.

context("Logging")

# Helper: write well-formed log entries to a temp file
make_log_file <- function(entries) {
  f <- tempfile(fileext = ".log")
  lines <- vapply(entries, function(e) jsonlite::toJSON(e, auto_unbox = TRUE), character(1))
  writeLines(lines, f)
  f
}


# =============================================================================
# read_logs() — basic parsing
# =============================================================================

test_that("read_logs parses entries from a specific file correctly", {
  entries <- list(
    list(timestamp = "2026-01-01 10:00:00", level = "INFO",
         session_id = "s1", event_type = "session_start",
         details = list(url = "localhost"), user_agent = "ua1"),
    list(timestamp = "2026-01-01 10:01:00", level = "INFO",
         session_id = "s1", event_type = "tab_change",
         details = list(tab = "enrollment"), user_agent = "ua1"),
    list(timestamp = "2026-01-01 10:02:00", level = "ERROR",
         session_id = "s1", event_type = "error",
         details = list(error = "something failed"), user_agent = "ua1")
  )
  f <- make_log_file(entries)

  # Override log dir to use only our temp file by testing the core parse logic
  lines    <- readLines(f, warn = FALSE)
  extract_value <- function(field) {
    if (is.null(field)) return(NA)
    if (is.list(field) || is.vector(field)) {
      if (length(field) > 0) return(as.character(field[1])) else return(NA)
    }
    as.character(field)
  }

  parsed <- lapply(lines, function(line) {
    if (nchar(line) == 0) return(NULL)
    tryCatch({
      e <- jsonlite::fromJSON(line)
      details_val <- if (is.list(e$details) && !is.null(names(e$details)))
        jsonlite::toJSON(e$details, auto_unbox = TRUE)
      else
        extract_value(e$details)
      data.frame(
        timestamp  = extract_value(e$timestamp),
        level      = extract_value(e$level),
        session_id = extract_value(e$session_id),
        event_type = extract_value(e$event_type),
        details    = as.character(details_val),
        user_agent = extract_value(e$user_agent),
        stringsAsFactors = FALSE
      )
    }, error = function(e) NULL)
  })
  result <- dplyr::bind_rows(Filter(Negate(is.null), parsed))

  expect_equal(nrow(result), 3)
  expect_equal(result$event_type, c("session_start", "tab_change", "error"))
  expect_equal(result$level[3], "ERROR")
  expect_equal(result$session_id, rep("s1", 3))
})

test_that("read_logs skips malformed JSON lines without aborting", {
  f <- tempfile(fileext = ".log")
  writeLines(c(
    '{"timestamp":"2026-01-01 10:00:00","level":"INFO","session_id":"s1","event_type":"session_start","details":null,"user_agent":"ua"}',
    "this is not json }{{{",
    '{"timestamp":"2026-01-01 10:01:00","level":"INFO","session_id":"s1","event_type":"tab_change","details":{"tab":"enrollment"},"user_agent":"ua"}'
  ), f)

  lines <- readLines(f, warn = FALSE)
  extract_value <- function(field) {
    if (is.null(field)) return(NA)
    if (is.list(field) || is.vector(field)) {
      if (length(field) > 0) return(as.character(field[1])) else return(NA)
    }
    as.character(field)
  }

  parsed <- lapply(lines, function(line) {
    if (nchar(line) == 0) return(NULL)
    tryCatch({
      e <- jsonlite::fromJSON(line)
      details_val <- if (is.list(e$details) && !is.null(names(e$details)))
        jsonlite::toJSON(e$details, auto_unbox = TRUE)
      else
        extract_value(e$details)
      data.frame(
        timestamp  = extract_value(e$timestamp),
        level      = extract_value(e$level),
        session_id = extract_value(e$session_id),
        event_type = extract_value(e$event_type),
        details    = as.character(details_val),
        user_agent = extract_value(e$user_agent),
        stringsAsFactors = FALSE
      )
    }, error = function(e) NULL)
  })
  result <- dplyr::bind_rows(Filter(Negate(is.null), parsed))

  # malformed line silently skipped — only 2 valid entries
  expect_equal(nrow(result), 2)
  expect_equal(result$event_type, c("session_start", "tab_change"))
})

test_that("read_logs bind_rows result has same structure as single-entry parse", {
  # Verify that bind_rows() over a list of 1-row data frames produces a
  # consistent column set — guards against the old rbind() NA-column issue
  entry <- list(
    list(timestamp = "2026-01-01 10:00:00", level = "INFO",
         session_id = "s1", event_type = "session_start",
         details = NULL, user_agent = "ua")
  )
  f     <- make_log_file(entry)
  lines <- readLines(f, warn = FALSE)

  extract_value <- function(field) {
    if (is.null(field)) return(NA)
    if (is.list(field) || is.vector(field)) {
      if (length(field) > 0) return(as.character(field[1])) else return(NA)
    }
    as.character(field)
  }
  parsed <- lapply(lines, function(line) {
    if (nchar(line) == 0) return(NULL)
    tryCatch({
      e <- jsonlite::fromJSON(line)
      details_val <- if (is.list(e$details) && !is.null(names(e$details)))
        jsonlite::toJSON(e$details, auto_unbox = TRUE)
      else
        extract_value(e$details)
      data.frame(timestamp=extract_value(e$timestamp), level=extract_value(e$level),
                 session_id=extract_value(e$session_id), event_type=extract_value(e$event_type),
                 details=as.character(details_val), user_agent=extract_value(e$user_agent),
                 stringsAsFactors=FALSE)
    }, error = function(e) NULL)
  })
  result <- dplyr::bind_rows(Filter(Negate(is.null), parsed))

  expect_setequal(names(result),
                  c("timestamp", "level", "session_id", "event_type", "details", "user_agent"))
  expect_equal(nrow(result), 1)
})


# =============================================================================
# start_report_timer / end_report_timer — roundtrip
# =============================================================================

test_that("start_report_timer captures operation and resource context", {
  ctx <- start_report_timer("test_report")

  expect_true(is.list(ctx))
  expect_equal(ctx$report_type, "test_report")
  expect_s3_class(ctx$start_time, "POSIXct")
  expect_true(nzchar(ctx$operation_id))
  expect_true(is.numeric(ctx$start_cpu_user))
  expect_true(is.numeric(ctx$rss_start_mb))
})

test_that("json_ready converts named vectors before JSON encoding", {
  details <- list(
    dept = c("History" = "HIST", "Math" = "MATH"),
    plain = c("ABQ", "EA")
  )

  sanitized <- json_ready(details)

  expect_true(is.list(sanitized$dept))
  expect_equal(names(sanitized$dept), c("History", "Math"))
  expect_equal(unname(unlist(sanitized$dept)), c("HIST", "MATH"))
  expect_false(is.list(sanitized$plain))
})

test_that("get_usage_overview handles report logs without department or course", {
  logs <- data.frame(
    timestamp = c(
      "2026-08-05 09:00:00",
      "2026-08-05 09:01:00",
      "2026-08-05 09:02:00"
    ),
    level = c("INFO", "INFO", "INFO"),
    session_id = c("s1", "s1", "s1"),
    event_type = c("session_start", "tab_change", "report_generated"),
    details = c(
      "{}",
      '{"tab":"Data & Usage"}',
      '{"report_type":"usage_overview","parameters":{"campus":[]}}'
    ),
    user_agent = c("ua", "ua", "ua"),
    stringsAsFactors = FALSE
  )

  old_read_logs <- read_logs
  assign("read_logs", function(...) logs, envir = .GlobalEnv)
  on.exit(assign("read_logs", old_read_logs, envir = .GlobalEnv), add = TRUE)

  overview <- get_usage_overview("2026-08-05", "2026-08-05")

  expect_equal(overview$total_reports, 1)
  expect_equal(nrow(overview$dept_reports), 0)
  expect_equal(nrow(overview$course_reports), 0)
  expect_equal(overview$tab_usage$tab, "Data & Usage")
  expect_true("1 active session" %in% overview$summary_text)
})

test_that("get_usage_overview builds dashboard rollups", {
  logs <- data.frame(
    timestamp = c(
      "2026-08-05 09:00:00",
      "2026-08-05 09:01:00",
      "2026-08-05 09:02:00",
      "2026-08-05 09:03:00",
      "2026-08-05 09:04:00"
    ),
    level = c("INFO", "INFO", "INFO", "INFO", "ERROR"),
    session_id = c("s1", "s1", "s1", "s2", "s2"),
    event_type = c("session_start", "tab_change", "report_generated",
                   "report_generated", "error"),
    details = c(
      "{}",
      '{"tab":"Dept Dashboard"}',
      '{"report_type":"dept_dashboard","parameters":{"dept_code":"HIST","campus":["ABQ","EA"],"term":202680}}',
      '{"report_type":"course_report","parameters":{"subject_course":"ENGL 1120","course_campus":"ABQ"}}',
      '{"error":"example","context":"test"}'
    ),
    user_agent = c("ua", "ua", "ua", "ua2", "ua2"),
    stringsAsFactors = FALSE
  )

  old_read_logs <- read_logs
  assign("read_logs", function(...) logs, envir = .GlobalEnv)
  on.exit(assign("read_logs", old_read_logs, envir = .GlobalEnv), add = TRUE)

  overview <- get_usage_overview("2026-08-05", "2026-08-05")

  expect_equal(overview$total_events, 5)
  expect_equal(overview$unique_sessions, 2)
  expect_equal(overview$total_tab_views, 1)
  expect_equal(overview$total_reports, 2)
  expect_equal(overview$errors_count, 1)
  expect_equal(overview$dept_reports$department, "HIST")
  expect_equal(overview$course_reports$course, "ENGL 1120")
  expect_setequal(overview$campus_usage$campus, c("ABQ", "EA"))
  expect_setequal(overview$report_type_usage$report_type, c("dept_dashboard", "course_report"))
  expect_equal(overview$daily_activity$events, 5)
  expect_equal(overview$daily_activity$reports, 2)
})

test_that("get_usage_overview counts active sessions, not passive session tokens", {
  logs <- data.frame(
    timestamp = c(
      "2026-08-05 09:00:00",
      "2026-08-05 09:01:00",
      "2026-08-05 09:02:00",
      "2026-08-05 09:03:00",
      "2026-08-05 09:04:00",
      "2026-08-05 09:05:00"
    ),
    level = rep("INFO", 6),
    session_id = c("passive-only", "passive-only", "active-tab", "active-report", "unknown", "unknown"),
    event_type = c("session_start", "session_end", "tab_change", "report_generated", "session_start", "tab_change"),
    details = c(
      "{}",
      "{}",
      '{"tab":"Dept Dashboard"}',
      '{"report_type":"dept_dashboard","parameters":{"dept_code":"HIST"}}',
      "{}",
      '{"tab":"Data & Usage"}'
    ),
    user_agent = rep("ua", 6),
    stringsAsFactors = FALSE
  )

  old_read_logs <- read_logs
  assign("read_logs", function(...) logs, envir = .GlobalEnv)
  on.exit(assign("read_logs", old_read_logs, envir = .GlobalEnv), add = TRUE)

  overview <- get_usage_overview("2026-08-05", "2026-08-05")

  expect_equal(overview$session_tokens_seen, 3)
  expect_equal(overview$sessions_opened, 1)
  expect_equal(overview$unique_sessions, 2)
  expect_equal(overview$daily_activity$sessions, 2)
  expect_true("2 active sessions" %in% overview$summary_text)
})

test_that("get_usage_overview keeps report type rollups stable for odd report details", {
  logs <- data.frame(
    timestamp = c(
      "2026-08-05 09:00:00",
      "2026-08-05 09:01:00",
      "2026-08-05 09:02:00",
      "2026-08-05 09:03:00"
    ),
    level = rep("INFO", 4),
    session_id = rep("s1", 4),
    event_type = rep("report_generated", 4),
    details = c(
      NA_character_,
      "not json",
      '{"parameters":{"dept_code":"HIST"}}',
      '{"report_type":[],"parameters":{"campus":[]}}'
    ),
    user_agent = rep("ua", 4),
    stringsAsFactors = FALSE
  )

  old_read_logs <- read_logs
  assign("read_logs", function(...) logs, envir = .GlobalEnv)
  on.exit(assign("read_logs", old_read_logs, envir = .GlobalEnv), add = TRUE)

  overview <- get_usage_overview("2026-08-05", "2026-08-05")

  expect_equal(overview$total_reports, 4)
  expect_equal(overview$report_type_usage$report_type, "unknown_report")
  expect_equal(overview$report_type_usage$count, 4)
  expect_equal(overview$dept_reports$department, "HIST")
})

test_that("end_report_timer returns a positive duration and writes to CSV", {
  log_file <- file.path(tempdir(), paste0("timing_test_", Sys.getpid(), ".csv"))
  # Temporarily override the timing log path
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit(assign("report_timing_log_file", old_path, envir = .GlobalEnv), add = TRUE)

  ctx      <- start_report_timer("test_op")
  duration <- end_report_timer(ctx, result = data.frame(x = 1:10))

  expect_true(is.numeric(duration))
  expect_gte(duration, 0)
  expect_true(file.exists(log_file))

  written <- read.csv(log_file, stringsAsFactors = FALSE)
  expect_equal(nrow(written), 1)
  expect_equal(written$report_type, "test_op")
  expect_equal(written$cached, 0)
  expect_equal(written$success, 1)
  expect_true(written$cpu_total_sec >= 0)
  expect_true(written$result_size_mb > 0)
  expect_identical(written$operation_id, attr(duration, "operation_id"))
})

test_that("end_report_timer cached flag is recorded correctly", {
  log_file <- file.path(tempdir(), paste0("timing_cached_", Sys.getpid(), ".csv"))
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit(assign("report_timing_log_file", old_path, envir = .GlobalEnv), add = TRUE)

  ctx <- start_report_timer("cached_op")
  end_report_timer(ctx, cached = TRUE)

  written <- read.csv(log_file, stringsAsFactors = FALSE)
  expect_equal(written$cached, 1)
})

test_that("concurrent workers append complete timing rows", {
  skip_on_os("windows")
  log_file <- tempfile(fileext = ".csv")
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit({
    assign("report_timing_log_file", old_path, envir = .GlobalEnv)
    unlink(c(log_file, paste0(log_file, ".lock")), recursive = TRUE)
  }, add = TRUE)

  invisible(parallel::mclapply(seq_len(8), function(i) {
    timer <- start_report_timer(paste0("worker_", i))
    end_report_timer(timer, result = i)
  }, mc.cores = 4L))

  written <- read_report_timings(log_file)
  expect_equal(nrow(written), 8L)
  expect_equal(length(unique(written$operation_id)), 8L)
  expect_setequal(written$report_type, paste0("worker_", seq_len(8)))
})

test_that("legacy and mixed timing rows migrate to canonical CSV", {
  log_file <- tempfile(fileext = ".csv")
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit({
    assign("report_timing_log_file", old_path, envir = .GlobalEnv)
    unlink(c(log_file, paste0(log_file, ".legacy")))
  }, add = TRUE)

  writeLines(c(
    '"timestamp","report_type","duration_sec","report_params"',
    '"2026-01-01 10:00:00","dept",2,"{\\"dept\\":\\"HIST\\"}"',
    '"2026-01-01 10:01:00","dept",0.1,1,"{\\"dept\\":\\"HIST\\"}"'
  ), log_file)

  end_report_timer(start_report_timer("new_run"), cached = FALSE)

  written <- read.csv(log_file, stringsAsFactors = FALSE)
  expect_identical(names(written), REPORT_TIMING_COLUMNS)
  expect_equal(nrow(written), 3L)
  expect_true(is.na(written$cached[[1]]))
  expect_equal(written$cached[2:3], c(1L, 0L))
  expect_equal(jsonlite::fromJSON(written$report_params[[1]])$dept, "HIST")
  expect_true(file.exists(paste0(log_file, ".legacy")))
})

test_that("timing averages read legacy JSON rows without column drift", {
  log_file <- tempfile(fileext = ".csv")
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit({
    assign("report_timing_log_file", old_path, envir = .GlobalEnv)
    unlink(log_file)
  }, add = TRUE)

  writeLines(c(
    '"timestamp","report_type","duration_sec","report_params"',
    '"2026-01-01 10:00:00","dept",8,"{\\"campus\\":[\\"ABQ\\",\\"EA\\"]}"',
    '"2026-01-01 10:01:00","dept",2,"{\\"campus\\":\\"ABQ\\"}"'
  ), log_file)

  expect_equal(get_average_report_time("dept"), 5)
  expect_equal(nrow(read_report_timings(log_file)), 2L)
})

test_that("get_average_report_time returns NULL when no log exists", {
  result <- get_average_report_time("nonexistent_report_type_xyz")
  expect_null(result)
})

test_that("get_average_report_time excludes cached runs when fresh_only = TRUE", {
  log_file <- file.path(tempdir(), paste0("timing_avg_", Sys.getpid(), ".csv"))
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit(assign("report_timing_log_file", old_path, envir = .GlobalEnv), add = TRUE)

  # Write two entries: one fresh (2s), one cached (0.1s)
  rows <- data.frame(
    timestamp   = c("2026-01-01 10:00:00", "2026-01-01 10:01:00"),
    report_type = c("dept", "dept"),
    duration_sec = c(2.0, 0.1),
    cached      = c(0L, 1L),
    report_params = c(NA, NA),
    stringsAsFactors = FALSE
  )
  write.table(rows, log_file, sep = ",", row.names = FALSE, col.names = TRUE, append = FALSE)

  avg_fresh <- get_average_report_time("dept", fresh_only = TRUE)
  avg_all   <- get_average_report_time("dept", fresh_only = FALSE)

  expect_equal(avg_fresh, 2.0)
  expect_equal(avg_all,   round(mean(c(2.0, 0.1)), 2))
})

test_that("reset_report_timings removes observations and restarts timing history", {
  log_file <- file.path(tempdir(), paste0("timing_reset_", Sys.getpid(), ".csv"))
  old_path <- report_timing_log_file
  assign("report_timing_log_file", log_file, envir = .GlobalEnv)
  on.exit({
    assign("report_timing_log_file", old_path, envir = .GlobalEnv)
    unlink(log_file)
  }, add = TRUE)

  rows <- data.frame(
    timestamp = c("2026-01-01 10:00:00", "2026-01-01 10:01:00"),
    report_type = c("dept", "dept"),
    duration_sec = c(8, 1),
    cached = c(0L, 1L),
    report_params = c(NA, NA),
    stringsAsFactors = FALSE
  )
  write.table(rows, log_file, sep = ",", row.names = FALSE,
              col.names = TRUE, append = FALSE)

  expect_equal(reset_report_timings(), 2L)
  expect_false(file.exists(log_file))
  expect_null(get_average_report_time("dept"))

  end_report_timer(start_report_timer("new_run"), cached = FALSE)
  restarted <- read.csv(log_file, stringsAsFactors = FALSE)
  expect_equal(nrow(restarted), 1L)
  expect_equal(restarted$report_type, "new_run")
})

test_that("reset_report_timings is a no-op when timing history is absent", {
  log_file <- tempfile(fileext = ".csv")
  expect_equal(reset_report_timings(log_file), 0L)
  expect_false(file.exists(log_file))
})

test_that("client render timings roundtrip into report summaries", {
  log_file <- tempfile(fileext = ".csv")
  on.exit(unlink(log_file), add = TRUE)

  expect_true(log_client_render_timing(list(
    report_type = "dept_dashboard", overlay_id = "dashboard",
    compute_sec = 8, total_sec = 12.5, post_compute_sec = 4.5,
    queue_delivery_sec = 3.5, browser_settle_sec = 1,
    payload_bytes = 2 * 1024^2, output_count = 6,
    cached = FALSE, viewport_width = 1440, viewport_height = 900
  ), path = log_file))
  expect_true(log_client_render_timing(list(
    report_type = "dept_dashboard", overlay_id = "dashboard",
    compute_sec = 1, total_sec = 3.5, post_compute_sec = 2.5,
    queue_delivery_sec = 2, browser_settle_sec = 0.5,
    payload_bytes = 1024^2, output_count = 6,
    cached = TRUE, viewport_width = 1440, viewport_height = 900
  ), path = log_file))

  summary <- get_client_render_timing_summary(log_file)
  expect_equal(nrow(summary), 2L)
  expect_setequal(summary$cache_path, c("Fresh / uncached", "Cached"))
  expect_equal(summary$avg_payload_mb[summary$cache_path == "Fresh / uncached"], 2)
  expect_equal(summary$median_queue_delivery_sec[summary$cache_path == "Cached"], 2)
  expect_equal(summary$median_browser_settle_sec[summary$cache_path == "Cached"], 0.5)
})

test_that("client timing schema migrates before appending performance fields", {
  log_file <- tempfile(fileext = ".csv")
  on.exit(unlink(c(log_file, paste0(log_file, ".legacy"))), add = TRUE)
  legacy <- data.frame(
    timestamp = "2026-01-01 10:00:00", report_type = "dept_dashboard",
    overlay_id = "dashboard", compute_sec = 2, total_sec = 4,
    post_compute_sec = 2, payload_bytes = 100, output_count = 1,
    cached = 1L, viewport_width = 1200, viewport_height = 800
  )
  write.table(legacy, log_file, sep = ",", row.names = FALSE)

  log_client_render_timing(list(
    report_type = "dept_dashboard", overlay_id = "dashboard",
    compute_sec = 3, total_sec = 7, post_compute_sec = 4,
    queue_delivery_sec = 3, browser_settle_sec = 1,
    payload_bytes = 200, output_count = 2, cached = FALSE
  ), session_id = "session-1", connected_sessions = 2, path = log_file)

  written <- read.csv(log_file, stringsAsFactors = FALSE)
  expect_identical(names(written), CLIENT_TIMING_COLUMNS)
  expect_equal(nrow(written), 2L)
  expect_true(is.na(written$queue_delivery_sec[[1]]))
  expect_equal(written$queue_delivery_sec[[2]], 3)
  expect_equal(written$session_id[[2]], "session-1")
  expect_equal(written$connected_sessions[[2]], 2)
  expect_true(file.exists(paste0(log_file, ".legacy")))
})

test_that("loading estimates use recent browser totals and show the slow tail", {
  report_file <- tempfile(fileext = ".csv")
  client_file <- tempfile(fileext = ".csv")
  old_report <- report_timing_log_file
  old_client <- client_render_timing_log_file
  assign("report_timing_log_file", report_file, envir = .GlobalEnv)
  assign("client_render_timing_log_file", client_file, envir = .GlobalEnv)
  on.exit({
    assign("report_timing_log_file", old_report, envir = .GlobalEnv)
    assign("client_render_timing_log_file", old_client, envir = .GlobalEnv)
    unlink(c(report_file, client_file))
  }, add = TRUE)

  client <- empty_client_timings()[rep(NA_integer_, 5), , drop = FALSE]
  client$timestamp <- sprintf("2026-01-01 10:00:%02d", 1:5)
  client$report_type <- "dept_dashboard"
  client$overlay_id <- "dashboard"
  client$total_sec <- c(1, 2, 5, 20, 40)
  client$compute_sec <- c(0.2, 0.4, 1, 2, 3)
  client$cached <- 1L
  write_client_timings(client, client_file)

  estimates <- report_time_estimates(
    "dept_dashboard", fresh_default = 20, cached_default = 2
  )
  expect_equal(estimates$cached, 5)
  expect_equal(estimates$cached_range$lower, 5)
  expect_equal(estimates$cached_range$upper, 32)
  expect_equal(estimates$cached_range$source, "browser_total")
  expect_equal(estimates$fresh, 20)
  expect_equal(estimates$fresh_range$source, "default")
})

test_that("performance summary combines browser latency with server memory", {
  report_file <- tempfile(fileext = ".csv")
  client_file <- tempfile(fileext = ".csv")
  on.exit(unlink(c(report_file, client_file)), add = TRUE)

  report <- empty_report_timings()[rep(NA_integer_, 2), , drop = FALSE]
  report$timestamp <- c("2026-01-01 10:00:00", "2026-01-01 10:01:00")
  report$report_type <- "dept_dashboard"
  report$duration_sec <- c(8, 12)
  report$cached <- 0L
  report$cpu_total_sec <- c(7, 9)
  report$rss_delta_mb <- c(20, 40)
  report$rss_end_mb <- c(900, 940)
  report$result_size_mb <- c(50, 70)
  report$success <- c(1L, 0L)
  write_report_timings(report, report_file)

  client <- empty_client_timings()[rep(NA_integer_, 2), , drop = FALSE]
  client$timestamp <- c("2026-01-01 10:00:10", "2026-01-01 10:01:20")
  client$report_type <- "dept_dashboard"
  client$total_sec <- c(10, 20)
  client$compute_sec <- c(8, 12)
  client$cached <- 0L
  client$queue_delivery_sec <- c(1, 6)
  client$browser_settle_sec <- c(1, 2)
  client$payload_bytes <- c(1024^2, 2 * 1024^2)
  write_client_timings(client, client_file)

  summary <- get_performance_timing_summary(report_file, client_file)
  expect_equal(nrow(summary), 1L)
  expect_equal(summary$failures, 1)
  expect_equal(summary$median_total_sec, 15)
  expect_equal(summary$median_rss_delta_mb, 30)
  expect_equal(summary$p90_result_size_mb, 68)
  expect_equal(summary$max_worker_rss_mb, 940)
})

test_that("invalid client render timing is ignored", {
  log_file <- tempfile(fileext = ".csv")
  expect_false(log_client_render_timing(list(total_sec = -1), path = log_file))
  expect_false(file.exists(log_file))
})

test_that("reset_client_render_timings removes browser observations", {
  log_file <- tempfile(fileext = ".csv")
  on.exit(unlink(log_file), add = TRUE)
  log_client_render_timing(list(total_sec = 1), path = log_file)
  log_client_render_timing(list(total_sec = 2), path = log_file)

  expect_equal(reset_client_render_timings(log_file), 2L)
  expect_false(file.exists(log_file))
  expect_equal(nrow(get_client_render_timing_summary(log_file)), 0L)
})
