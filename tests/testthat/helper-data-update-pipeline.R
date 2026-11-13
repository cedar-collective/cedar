# What the tests in test-data-update-pipeline.R share: builders, option lists, constants.

# The script's fetch step, run on its own against a stand-in `docker` on the
# PATH. `compose ... run` behaves as `fetch` says (a shell snippet: the
# stand-in's stdout is mrgather's); `rm -f` records the container it was asked
# to remove and ends the running fetch, as removing the container does.
run_fetch_step <- function(files = character(0), fetch = "exit 0", today = "20261020",
                           time_limit = 60L) {
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  first <- grep("^report_file_glob\\(\\) \\{", script)
  last <- grep("^# ── Step 2: Parse raw data", script)
  stopifnot(length(first) == 1L, length(last) == 1L)
  block <- paste(script[first:(last - 1L)], collapse = "\n")
  root <- tempfile("mrgather fetch ")
  downloads <- file.path(root, "downloads")
  bin <- file.path(root, "bin")
  dir.create(downloads, recursive = TRUE)
  dir.create(bin)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.create(file.path(downloads, files))
  docker <- file.path(bin, "docker")
  writeLines(c(
    "#!/usr/bin/env bash",
    'if [[ "$1" == "rm" ]]; then',
    '  echo "$3" > "$FAKE_ROOT/removed"',
    '  kill "$(cat "$FAKE_ROOT/fetch.pid")" 2>/dev/null',
    "  exit 0",
    "fi",
    'echo "$$" > "$FAKE_ROOT/fetch.pid"',
    'echo "$*" > "$FAKE_ROOT/fetch.args"',
    'cd "$FAKE_ROOT/downloads" || exit 9',
    fetch
  ), docker)
  Sys.chmod(docker, "755")
  code <- paste(
    paste0("export FAKE_ROOT=", shQuote(root)),
    paste0("export PATH=", shQuote(bin), ":$PATH"),
    paste0("MRGATHER_DATA_DIR=", shQuote(downloads)),
    paste0("TODAY=", today), "MODE=local", "DRY_RUN=false", "SECONDS=0", "STEP_START=0",
    "MRGATHER_DIR=/nonexistent", "START_TERM=202480", "END_TERM=202510",
    "REPORTS=(cl desr)", "SKIP_FETCH=true", "FETCH_RC=0", "FETCH_STATUS=OK", "FETCH_NOTE=",
    "FETCH_STOP_REASON=", paste0("FETCH_TIME_LIMIT=", time_limit), "FETCH_POLL_SECONDS=1",
    "MRGATHER_2FA_PROMPT='Please enter the 2FA code'",
    "REFRESH_CAN_CONTINUE=true",
    "record_step() { printf 'STEP:%s|%s\\n' \"$2\" \"$4\"; }",
    "log_step() { :; }; log_success() { :; }; log_warning() { :; }; log_error() { :; }",
    "run_cmd() { \"$@\"; }",
    block,
    "printf 'PARSE:%s\\n' \"$REPORTS_CSV\"",
    "printf 'TABLES:%s\\n' \"${TABLES_ARGS[*]}\"",
    sep = "\n"
  )
  # The step runs with no terminal on standard input, as it does under cron.
  out <- system2("bash", c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE, stdin = "")
  read_one <- function(name) {
    path <- file.path(root, name)
    if (file.exists(path)) readLines(path, warn = FALSE) else NA_character_
  }
  list(
    step = sub("^STEP:", "", out[startsWith(out, "STEP:")]),
    parse = sub("^PARSE:", "", out[startsWith(out, "PARSE:")]),
    tables = sub("^TABLES:", "", out[startsWith(out, "TABLES:")]),
    removed = read_one("removed"),
    args = read_one("fetch.args")
  )
}
