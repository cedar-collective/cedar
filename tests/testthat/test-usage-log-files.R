context("Usage log rotation, archiving, and bounded previews")

test_that("daily log names rotate without restarting the worker", {
  expect_equal(basename(usage_log_path("logs", as.Date("2026-09-04"))),
               "cedar_usage_20260904.log")
  expect_equal(basename(usage_log_path("logs", as.Date("2026-09-05"))),
               "cedar_usage_20260905.log")
})

test_that("one-day queries prune daily files and legacy JSON lines", {
  root <- tempfile("usage-files-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  entry <- function(day, id) jsonlite::toJSON(list(
    timestamp = paste(day, "12:00:00"), level = "INFO", session_id = id,
    event_type = "tab_change", details = list(tab = "Data & Usage")
  ), auto_unbox = TRUE)
  before <- entry("2026-09-03", "before")
  wanted <- entry("2026-09-04", "wanted")
  after <- entry("2026-09-05", "after")
  writeLines(before, file.path(root, "cedar_usage_20260903.log"))
  writeLines(wanted, file.path(root, "cedar_usage_20260904.log"))
  writeLines(after, file.path(root, "cedar_usage_20260905.log"))
  expect_equal(basename(usage_log_files(root, "2026-09-04", "2026-09-04")),
               "cedar_usage_20260904.log")
  expect_equal(filter_usage_log_lines(c(before, wanted, after), "2026-09-04", "2026-09-04"),
               as.character(wanted))
  expect_equal(read_logs("2026-09-04", "2026-09-04", root)$session_id, "wanted")
  # Old monthly workers can append next-month events: retain that compatibility.
  legacy <- file.path(root, "cedar_usage_202608.log")
  writeLines(c(entry("2026-08-31", "old"), entry("2026-09-04", "legacy")), legacy)
  Sys.setFileTime(legacy, as.POSIXct("2026-09-04 18:00:00"))
  expect_setequal(read_logs("2026-09-04", "2026-09-04", root)$session_id,
                  c("wanted", "legacy"))
  # A second query sees a same-day append, not a stale cached parse.
  write(entry("2026-09-04", "new"), file.path(root, "cedar_usage_20260904.log"), append = TRUE)
  expect_equal(nrow(read_logs("2026-09-04", "2026-09-04", root)), 3L)
})

test_that("archiving preserves bytes, history queries, and existing destinations", {
  root <- tempfile("usage-archive-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  old <- file.path(root, "cedar_usage_20260101.log")
  lines <- '{"timestamp":"2026-01-01 12:00:00","level":"INFO","session_id":"old","event_type":"session_start"}'
  writeLines(lines, old)
  Sys.setFileTime(old, as.POSIXct("2026-01-02 12:00:00"))
  archived <- cleanup_old_logs(root, 90L, as.Date("2026-09-04"))
  expect_length(archived, 1L)
  expect_false(file.exists(old))
  expect_equal(readLines(archived), lines)
  expect_equal(read_logs("2026-01-01", "2026-01-01", root)$session_id, "old")
  expect_length(usage_log_files(root, "2026-09-04", "2026-09-04"), 0L)
  expect_length(cleanup_old_logs(root, 90L, as.Date("2026-09-04")), 0L)
  writeLines("different content", old)
  Sys.setFileTime(old, as.POSIXct("2026-01-02 12:00:00"))
  expect_warning(cleanup_old_logs(root, 90L, as.Date("2026-09-04")), "without overwriting")
  expect_equal(readLines(old), "different content")
  expect_equal(readLines(archived), lines)
})

test_that("preview limits do not truncate the usage summary", {
  logs <- data.frame(timestamp = as.POSIXct("2026-09-04", tz = "UTC") + seq_len(600),
    level = "INFO", session_id = as.character(seq_len(600)),
    event_type = "session_start", details = "{}")
  preview <- recent_usage_log_entries(logs)
  expect_equal(nrow(preview), 500L)
  expect_equal(preview$session_id[[1]], "600")
  expect_equal(get_usage_stats(logs = logs)$total_sessions, 600L)
  expect_equal(nrow(logs), 600L)
})
