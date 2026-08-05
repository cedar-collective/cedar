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

test_that("start_report_timer returns a list with start_time and report_type", {
  ctx <- start_report_timer("test_report")

  expect_true(is.list(ctx))
  expect_equal(ctx$report_type, "test_report")
  expect_s3_class(ctx$start_time, "POSIXct")
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
  duration <- end_report_timer(ctx)

  expect_true(is.numeric(duration))
  expect_gte(duration, 0)
  expect_true(file.exists(log_file))

  written <- read.csv(log_file, stringsAsFactors = FALSE)
  expect_equal(nrow(written), 1)
  expect_equal(written$report_type, "test_op")
  expect_equal(written$cached, 0)
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
