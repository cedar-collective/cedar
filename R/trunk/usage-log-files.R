# Daily rotation and conservative file selection for the usage-log reader.
# Legacy monthly files remain readable, including sessions spanning month end.
usage_log_path <- function(log_dir, when = Sys.time()) {
  file.path(log_dir, paste0("cedar_usage_", format(when, "%Y%m%d"), ".log"))
}

usage_log_files <- function(log_dir, start_date = NULL, end_date = NULL) {
  directories <- c(log_dir, file.path(log_dir, "archive"))
  files <- unlist(lapply(directories, function(directory) {
    list.files(directory, pattern = "^cedar_usage_.*\\.log$", full.names = TRUE)
  }), use.names = FALSE)
  if (length(files) == 0L) return(character(0))
  names <- basename(files)
  daily <- grepl("^cedar_usage_[0-9]{8}\\.log$", names)
  day <- as.Date(rep(NA_character_, length(files)))
  day[daily] <- as.Date(sub("^cedar_usage_([0-9]{8})\\.log$", "\\1", names[daily]),
                        format = "%Y%m%d")
  # Only daily files have a strict filename/date contract. Legacy monthly
  # files can span month boundaries, so mtime is only a conservative upper edge.
  keep <- rep(TRUE, length(files))
  if (!is.null(start_date)) {
    start <- as.Date(start_date)
    upper <- as.Date(file.info(files)$mtime) + 1L
    monthly <- grepl("^cedar_usage_[0-9]{6}([^0-9]|$)", names)
    month_start <- as.Date(paste0(substr(names[monthly], 13L, 18L), "01"), "%Y%m%d")
    month_end <- as.Date(format(month_start + 31L, "%Y-%m-01")) - 1L
    upper[monthly] <- pmax(upper[monthly], month_end, na.rm = TRUE)
    upper[daily & !is.na(day)] <- day[daily & !is.na(day)]
    keep <- keep & (is.na(upper) | upper >= start)
  }
  if (!is.null(end_date)) {
    keep <- keep & (!daily | is.na(day) | day <= as.Date(end_date))
  }
  files[keep]
}

# Cheap timestamp filtering before decoding JSON saves parsing whole legacy
# months for a one-day view. Unknown formats still reach the tolerant parser.
filter_usage_log_lines <- function(lines, start_date = NULL, end_date = NULL) {
  pattern <- '"timestamp"[[:space:]]*:[[:space:]]*\\[?[[:space:]]*"([0-9]{4}-[0-9]{2}-[0-9]{2})'
  matches <- regexec(pattern, lines)
  values <- regmatches(lines, matches)
  dates <- vapply(values, function(value) if (length(value) >= 2L) value[[2]] else
                    NA_character_, character(1))
  keep <- rep(TRUE, length(lines))
  if (!is.null(start_date)) keep <- keep & (is.na(dates) | dates >= as.character(start_date))
  if (!is.null(end_date)) keep <- keep & (is.na(dates) | dates <= as.character(end_date))
  lines[keep]
}

recent_usage_log_entries <- function(logs, limit = 500L) {
  if (nrow(logs) == 0L) return(logs)
  head(logs[order(logs$timestamp, decreasing = TRUE), , drop = FALSE], limit)
}
