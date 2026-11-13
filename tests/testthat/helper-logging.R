# What the tests in test-logging.R share: builders, option lists, constants.

# Helper: write well-formed log entries to a temp file
make_log_file <- function(entries) {
  f <- tempfile(fileext = ".log")
  lines <- vapply(entries, function(e) jsonlite::toJSON(e, auto_unbox = TRUE), character(1))
  writeLines(lines, f)
  f
}
