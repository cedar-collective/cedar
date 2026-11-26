# These are workflow/runner input contracts, not institutional-data fixtures.

test_that("PR checks are read-only, secret-free, and independent of deployment", {
  path <- file.path(cedar_base_dir, ".github", "workflows", "pr-checks.yml")
  workflow <- yaml::read_yaml(path)
  text <- paste(readLines(path), collapse = "\n")
  expect_setequal(names(workflow$on), c("pull_request", "workflow_dispatch"))
  expect_equal(workflow$on$pull_request$branches, "main")
  expect_null(workflow$on$pull_request$paths)
  expect_null(workflow$on$pull_request[["paths-ignore"]])
  expect_identical(workflow$permissions, list(contents = "read"))
  expect_false(grepl("secrets\\.|pull_request_target|self-hosted|ssh-action|docker-compose.yml", text))
  expect_setequal(names(workflow$jobs), "synthetic-checks")

  job <- workflow$jobs[["synthetic-checks"]]
  expect_identical(job$name, "Synthetic checks")
  expect_identical(job[["runs-on"]], "ubuntu-24.04")
  expect_lte(job[["timeout-minutes"]], 35)
  checkout <- Filter(function(step) identical(step$uses, "actions/checkout@v4"), job$steps)[[1]]
  expect_identical(checkout$with[["persist-credentials"]], FALSE)
  expect_null(checkout$with$ref) # Test GitHub's proposed merge, not a different checkout.
  build <- Filter(function(step) identical(step$uses, "docker/build-push-action@v6"), job$steps)[[1]]
  expect_identical(build$with$push, FALSE)
  expect_identical(build$with$load, TRUE)
  expect_identical(build$with$tags, job$env$CEDAR_DEV_IMAGE)
  expect_identical(job$env$CEDAR_URL, "http://127.0.0.1:3838/")
})

test_that("PR checks run the full standard gate against an isolated synthetic app", {
  workflow <- yaml::read_yaml(file.path(cedar_base_dir, ".github", "workflows", "pr-checks.yml"))
  steps <- workflow$jobs[["synthetic-checks"]]$steps
  commands <- vapply(steps, function(step) step$run %||% "", character(1))
  start <- grep("up -d --no-build", commands, fixed = TRUE)
  gate <- grep("./run-tests.sh --test-image cedar:pr-test --e2e demo", commands, fixed = TRUE)
  expect_length(start, 1)
  expect_length(gate, 1)
  expect_lt(start, gate)
  expect_true(all(grepl("--env-file /dev/null -p cedar-demo -f compose.dev.yml",
                       commands[grepl("docker compose", commands)], fixed = TRUE)))
  expect_false(any(grepl("testthat::|node tests/e2e/.*test.mjs", commands)))
  cleanup <- grep(" down$", commands)
  expect_length(cleanup, 1)
  expect_identical(steps[[cleanup]][["if"]], "always()")
  expect_lt(gate, cleanup)
  upload <- Filter(function(step) identical(step$uses, "actions/upload-artifact@v4"), steps)[[1]]
  expect_identical(upload[["if"]], "always()")
  expect_equal(upload$with[["retention-days"]], 7)
})

test_that("the Docker R option preserves the standard runner and rejects malformed arguments", {
  runner <- file.path(cedar_base_dir, "run-tests.sh")
  expect_equal(system2("bash", c("-n", shQuote(runner))), 0)
  text <- paste(readLines(runner), collapse = "\n")
  expect_equal(sum(gregexpr("testthat::test_dir", text, fixed = TRUE)[[1]] > 0), 1)
  expect_match(text, '--vanilla -e "$R_TEST_CODE"', fixed = TRUE)
  expect_match(text, '--entrypoint Rscript "$TEST_IMAGE"', fixed = TRUE)
  help <- system2("bash", c(shQuote(runner), "--help"), stdout = TRUE)
  expect_true(any(grepl("--test-image", help, fixed = TRUE)))
  for (args in list("--test-image", c("--test-image", "--e2e"), c("demo", "nav"))) {
    status <- system2("bash", c(shQuote(runner), args), stdout = FALSE, stderr = FALSE)
    expect_equal(status, 2)
  }
})

test_that("browser selection is narrow by default and failures are never retried", {
  # Executable doubles exercise the real runner's dispatch and exit status.
  # No R subprocess suite, Docker daemon, sleep, or browser is needed here.
  bin <- withr::local_tempdir()
  log <- file.path(bin, "calls")
  stub <- c("#!/bin/bash",
            'printf "%s %s\\n" "${0##*/}" "$*" >> "$CEDAR_RUNNER_LOG"',
            'if [ "${0##*/}" = node ] && [ -n "$CEDAR_RUNNER_FAIL" ] && [[ "$*" = *"$CEDAR_RUNNER_FAIL"* ]]; then exit 1; fi',
            "exit 0")
  for (command in c("node", "Rscript", "docker", "curl", "sleep")) {
    path <- file.path(bin, command)
    writeLines(stub, path)
    Sys.chmod(path, "0755")
  }
  withr::local_envvar(c(PATH = paste(bin, Sys.getenv("PATH"), sep = .Platform$path.sep),
                      CEDAR_RUNNER_LOG = log, CEDAR_RUNNER_FAIL = ""))
  runner <- file.path(cedar_base_dir, "run-tests.sh")
  run <- function(args, fail = "") {
    writeLines(character(), log)
    withr::local_envvar(c(CEDAR_RUNNER_FAIL = fail))
    status <- system2("bash", c(shQuote(runner), args), stdout = FALSE, stderr = FALSE)
    list(status = status, calls = readLines(log))
  }
  browser_calls <- function(result) grep("^node .*test.mjs", result$calls, value = TRUE)

  smoke <- run("--e2e")
  expect_equal(smoke$status, 0)
  expect_equal(browser_calls(smoke), "node tests/e2e/reports-smoke.test.mjs smoke")
  expect_equal(browser_calls(run(c("--all", "smoke"))), browser_calls(smoke))
  expect_equal(browser_calls(run(c("--e2e", "headcount"))),
               "node tests/e2e/reports-smoke.test.mjs headcount")
  expect_equal(browser_calls(run(c("--e2e", "reports"))),
               "node tests/e2e/reports-smoke.test.mjs all")
  release <- run("--all")
  expect_equal(release$status, 0)
  expect_true("node tests/e2e/reports-smoke.test.mjs all" %in% browser_calls(release))
  expect_true("node tests/e2e/credit-timeline.test.mjs" %in% browser_calls(release))
  expect_false(any(grepl("demo.test.mjs", browser_calls(release), fixed = TRUE)))

  failed <- run("--all", fail = "reports-smoke.test.mjs")
  expect_equal(failed$status, 1)
  expect_equal(sum(grepl("reports-smoke.test.mjs", browser_calls(failed), fixed = TRUE)), 1)
  expect_false(any(grepl("nav.test.mjs", browser_calls(failed), fixed = TRUE)))
  for (args in list("nav", c("--e2e", "unknown-suite"))) {
    invalid <- run(args)
    expect_equal(invalid$status, 2)
    expect_length(invalid$calls, 0)
  }
})

test_that("the runner refuses a suite aimed at the wrong data surface", {
  # Both stacks serve 3838, so only the served page says which one is up.
  # Institutional assertions against synthetic records fail in ways that look
  # like broken features, so the runner must catch it before any browser starts.
  bin <- withr::local_tempdir()
  log <- file.path(bin, "calls")
  page <- file.path(bin, "page.html")
  stub <- c("#!/bin/bash",
            'printf "%s %s\\n" "${0##*/}" "$*" >> "$CEDAR_RUNNER_LOG"',
            # -I is the liveness probe; a bodied GET is the identity probe.
            'if [ "${0##*/}" = curl ] && [[ "$*" != *-sfI* ]]; then cat "$CEDAR_FAKE_PAGE"; fi',
            "exit 0")
  for (command in c("node", "Rscript", "docker", "curl", "sleep")) {
    path <- file.path(bin, command)
    writeLines(stub, path)
    Sys.chmod(path, "0755")
  }
  runner <- file.path(cedar_base_dir, "run-tests.sh")
  run <- function(args) {
    writeLines(character(), log)
    status <- system2("bash", c(shQuote(runner), args), stdout = FALSE, stderr = FALSE)
    list(status = status, calls = readLines(log))
  }
  browser_calls <- function(result) grep("^node .*test.mjs", result$calls, value = TRUE)
  withr::local_envvar(c(PATH = paste(bin, Sys.getenv("PATH"), sep = .Platform$path.sep),
                        CEDAR_RUNNER_LOG = log, CEDAR_RUNNER_FAIL = "",
                        CEDAR_FAKE_PAGE = page))

  # Pad past the pipe buffer. A short page cannot express the failure this
  # guards: matching by piping into `grep -q` dies of SIGPIPE under pipefail
  # once the body is big enough that the writer is still going when grep exits,
  # so a real 488KB app page reported "unknown" while a two-line stub passed.
  filler <- paste(rep("<span>cedar</span>", 20000), collapse = "")
  write_page <- function(...) writeLines(c(..., filler), page)

  # The synthetic app is up; an institutional suite must not run against it.
  write_page('<link href="cedar-custom.css">',
             '<div id="cedar_demo_banner">Synthetic data</div>')
  mismatch <- run(c("--e2e", "nav"))
  expect_equal(mismatch$status, 1)
  expect_length(browser_calls(mismatch), 0)

  # demo is exactly what that app is for.
  expect_equal(browser_calls(run(c("--e2e", "demo"))), "node tests/e2e/demo.test.mjs")

  # Institutional app up: the pairing reverses.
  write_page('<link href="cedar-custom.css"><div>CEDAR</div>')
  expect_equal(browser_calls(run(c("--e2e", "nav"))), "node tests/e2e/nav.test.mjs")
  expect_equal(browser_calls(run(c("--e2e", "demo"))), character(0))

  # A page without the app's own marker is a not-yet-booted worker, not an
  # institutional app. Guessing "institutional" there made the runner refuse the
  # demo suite while the demo app was starting up.
  write_page("<html>starting</html>")
  expect_equal(browser_calls(run(c("--e2e", "nav"))), "node tests/e2e/nav.test.mjs")
})

test_that("a fresh run restarts the app, waits for its build-ahead and times its first sessions first", {
  # Executable doubles, as above. docker answers the two questions the runner
  # asks of it: which container publishes the app's port, and what its log
  # says. Every other browser run meets a process already in use, which is how
  # a test driver that raced a new one went unseen (ISSUES I85).
  bin <- withr::local_tempdir()
  log <- file.path(bin, "calls")
  app_log <- file.path(bin, "app.log")
  stub <- c("#!/bin/bash",
            'printf "%s %s\\n" "${0##*/}" "$*" >> "$CEDAR_RUNNER_LOG"',
            'if [ "${0##*/}" = docker ] && [ "$1" = ps ]; then echo "$CEDAR_FAKE_CONTAINER"; fi',
            'if [ "${0##*/}" = docker ] && [ "$1" = logs ]; then cat "$CEDAR_FAKE_APP_LOG"; fi',
            "exit 0")
  for (command in c("node", "Rscript", "docker", "curl", "sleep")) {
    path <- file.path(bin, command)
    writeLines(stub, path)
    Sys.chmod(path, "0755")
  }
  withr::local_envvar(c(PATH = paste(bin, Sys.getenv("PATH"), sep = .Platform$path.sep),
                        CEDAR_RUNNER_LOG = log, CEDAR_FAKE_APP_LOG = app_log,
                        CEDAR_FAKE_CONTAINER = "cedar-test-app",
                        CEDAR_BUILD_AHEAD_TIMEOUT = "1"))
  runner <- file.path(cedar_base_dir, "run-tests.sh")
  run <- function(args) {
    writeLines(character(), log)
    status <- system2("bash", c(shQuote(runner), args), stdout = FALSE, stderr = FALSE)
    list(status = status, calls = readLines(log))
  }
  browser_calls <- function(result) grep("^node .*test.mjs", result$calls, value = TRUE)
  first_sessions <- "node tests/e2e/fresh-start.test.mjs"
  built <- c("[global.R] Downstream built ahead for: no course",
             "[preload] 1 of 5: graduation_dashboard, ABQ: built (15.6s)",
             "2026-11-25T21:55:40Z [preload] 5 of 5: dfw_dashboard, ABQ, EA: built (16.2s)")

  writeLines(built, app_log)
  fresh <- run(c("--e2e", "--fresh"))
  expect_equal(fresh$status, 0)
  expect_equal(browser_calls(fresh), first_sessions)
  expect_true("docker restart cedar-test-app" %in% fresh$calls)
  expect_lt(match("docker restart cedar-test-app", fresh$calls), match(first_sessions, fresh$calls))
  expect_false("node tests/e2e/warmup.mjs" %in% fresh$calls)

  # A suite named with it runs after the first sessions, never before.
  expect_equal(browser_calls(run(c("--e2e", "--fresh", "nav"))),
               c(first_sessions, "node tests/e2e/nav.test.mjs"))

  # A rebuilt container is already a new process: no restart on top of it.
  rebuilt <- run(c("--all", "--fresh"))
  expect_equal(browser_calls(rebuilt), first_sessions)
  expect_false("docker restart cedar-test-app" %in% rebuilt$calls)

  # It is no part of a tour, and means nothing on a process already in use.
  expect_false(first_sessions %in% browser_calls(run("--all")))
  unasked <- run(c("--e2e", "fresh-start"))
  expect_equal(unasked$status, 2)
  expect_length(unasked$calls, 0)

  # The build-ahead has not logged its last job: a session opened now would
  # wait behind the job running, so nothing is timed.
  writeLines(built[1:2], app_log)
  building <- run(c("--e2e", "--fresh"))
  expect_equal(building$status, 1)
  expect_length(browser_calls(building), 0)

  # No container publishes the app's port: nothing to restart, and it says so
  # before any browser starts.
  writeLines(built, app_log)
  withr::local_envvar(c(CEDAR_FAKE_CONTAINER = ""))
  absent <- run(c("--e2e", "--fresh"))
  expect_equal(absent$status, 1)
  expect_false(any(grepl("^docker restart", absent$calls)))
  expect_length(browser_calls(absent), 0)
})

test_that("after a failed browser stage the runner says what the app's container shows", {
  # Executable doubles, as above. A suite that fails names the step that was
  # running, and the cause is often elsewhere: the app's R process killed for
  # memory and another started, the container restarted or gone, the disk
  # full (docs/developers/e2e-testing.md). docker, df and curl answer here
  # what they would in each case; the failing suite is what changes the app.
  testthat::local_edition(3)
  bin <- withr::local_tempdir()
  log <- file.path(bin, "calls")
  state <- file.path(bin, "state")
  stub <- c("#!/bin/bash",
            'printf "%s %s\\n" "${0##*/}" "$*" >> "$CEDAR_RUNNER_LOG"',
            'did="$(cat "$CEDAR_FAKE_STATE" 2>/dev/null)"',
            'if [ "${0##*/}" = node ] && [ -n "$CEDAR_RUNNER_FAIL" ] && [[ "$*" = *"$CEDAR_RUNNER_FAIL"* ]]; then',
            '  printf "%s" "$CEDAR_FAKE_HAPPENS" > "$CEDAR_FAKE_STATE"; exit 1',
            "fi",
            'case "${0##*/} $*" in',
            '  "docker ps"*) [ "$did" = gone ] || echo cedar-test-app ;;',
            # shiny-server's R process is the one running its SockJSAdapter.R.
            '  "docker exec"*"pgrep -f SockJSAdapter"*) case "$did" in killed) echo 3120 ;; dead) ;; *) echo 275 ;; esac ;;',
            '  "docker inspect"*OOMKilled*) if [ "$did" = killed ]; then echo true; else echo false; fi ;;',
            '  "docker inspect"*StartedAt*) if [ "$did" = restarted ]; then echo 2026-11-25T10:20:00Z; else echo 2026-11-25T10:00:00Z; fi ;;',
            '  "docker stats --no-stream --format {{.Name}}  {{.MemUsage}} "*) echo "cedar-test-app  3.41GiB / 3.83GiB" ;;',
            '  "df "*) printf "Filesystem 1024-blocks Used Available Capacity Mounted\\n/dev/disk 9 9 %s 50%% /\\n" "$CEDAR_FAKE_FREE_KB" ;;',
            '  curl*http_code*) printf "%s" "$CEDAR_FAKE_HTTP" ;;',
            "esac",
            "exit 0")
  for (command in c("node", "Rscript", "docker", "curl", "sleep", "df")) {
    path <- file.path(bin, command)
    writeLines(stub, path)
    Sys.chmod(path, "0755")
  }
  withr::local_envvar(c(PATH = paste(bin, Sys.getenv("PATH"), sep = .Platform$path.sep),
                        CEDAR_RUNNER_LOG = log, CEDAR_FAKE_STATE = state))
  runner <- file.path(cedar_base_dir, "run-tests.sh")
  # What the runner printed about the container: from its heading to the next
  # empty line.
  run <- function(fail = "nav.test.mjs", happens = "", free_kb = "10485760", http = "200") {
    unlink(state)
    withr::local_envvar(c(CEDAR_RUNNER_FAIL = fail, CEDAR_FAKE_HAPPENS = happens,
                          CEDAR_FAKE_FREE_KB = free_kb, CEDAR_FAKE_HTTP = http))
    printed <- suppressWarnings(system2("bash", c(shQuote(runner), "--e2e", "nav"), stdout = TRUE, stderr = FALSE))
    from <- grep("^What the app's container says", printed)
    said <- if (length(from) == 0L) character(0) else {
      rest <- printed[from[1]:length(printed)]
      rest[seq_len(match("", rest, nomatch = length(rest) + 1L) - 1L)]
    }
    list(status = attr(printed, "status") %||% 0L, said = said)
  }

  killed <- run(happens = "killed")
  dead <- run(happens = "dead")
  restarted <- run(happens = "restarted")
  nothing <- run()
  gone <- run(happens = "gone")
  full <- run(free_kb = "204800", http = "500")
  # Explaining a failure never changes it.
  expect_equal(c(killed$status, dead$status, restarted$status, nothing$status, gone$status, full$status),
               rep(1L, 6))

  expect_snapshot(writeLines(c(
    "== The R process was killed for memory and another has started", killed$said,
    "", "== The R process is gone and none has started yet", dead$said,
    "", "== The container restarted", restarted$said,
    "", "== Nothing happened to the container", nothing$said,
    "", "== The container stopped", gone$said,
    "", "== The disk is nearly full and the app answers 500", full$said
  )))

  # A run that passes says nothing about the container.
  passed <- run(fail = "")
  expect_equal(passed$status, 0L)
  expect_length(passed$said, 0L)
})

test_that("the instructor-gate password is handed from .env to the Shiny worker", {
  # ISSUES.md I55: .env and .Renviron are kept out of the image, and
  # shiny-server starts its R worker with a clean environment. The password
  # reaches the app only if Compose passes it to the container and the
  # entrypoint writes it where the worker's R reads it.
  # Read as text: yaml::read_yaml() warns on the build context's bare ".".
  compose <- readLines(file.path(cedar_base_dir, "docker-compose.yml"))
  expect_length(grep("^      CEDAR_DFW_PASSWORD: \\$\\{CEDAR_DFW_PASSWORD:-\\}$", compose), 1L)
  ignored <- readLines(file.path(cedar_base_dir, ".dockerignore"))
  expect_true(all(c(".env", ".Renviron") %in% ignored))
  entrypoint <- readLines(file.path(cedar_base_dir, "entrypoint.sh"))
  writes <- grep("CEDAR_DFW_PASSWORD='%s'", entrypoint, fixed = TRUE)
  starts <- grep("^exec /usr/bin/shiny-server", entrypoint)
  expect_length(writes, 1L)
  expect_true(any(grepl('worker_renviron="$HOME/.Renviron"', entrypoint, fixed = TRUE)))
  expect_lt(writes, starts)
})

test_that("the count of courses built ahead is handed from the environment to the Shiny worker", {
  # As the password above: a variable Compose passes to the container reaches
  # global.R only if the entrypoint writes it where the worker's R reads it.
  # Without that the app builds ten ahead whatever the environment says.
  compose <- readLines(file.path(cedar_base_dir, "docker-compose.yml"))
  expect_length(grep("^      CEDAR_PRELOAD_COURSES: \\$\\{CEDAR_PRELOAD_COURSES:-10\\}$", compose), 1L)
  entrypoint <- readLines(file.path(cedar_base_dir, "entrypoint.sh"))
  writes <- grep('printf "CEDAR_PRELOAD_COURSES=%s\\n"', entrypoint, fixed = TRUE)
  starts <- grep("^exec /usr/bin/shiny-server", entrypoint)
  expect_length(writes, 1L)
  expect_lt(writes, starts)
  global <- readLines(file.path(cedar_base_dir, "global.R"))
  expect_length(grep('Sys.getenv("CEDAR_PRELOAD_COURSES", "10")', global, fixed = TRUE), 1L)
})

# ISSUES I81, M70. The R suite cannot start the app, so both ends of the
# hand-over are read: Shiny runs the value of server.R's last line.
test_that("global.R compiles the server function and server.R's last line hands it to Shiny", {
  server_file <- parse(file.path(cedar_base_dir, "server.R"))
  expect_identical(deparse(server_file[[length(server_file)]]),
                   'cedar_server_to_run(server, cedar_compiled_server, "server.R")')

  global <- readLines(file.path(cedar_base_dir, "global.R"), warn = FALSE)
  nothing_yet <- which(global == "cedar_compiled_server <- NULL")
  read <- which(global == 'source("server.R")')
  compiled <- which(global == 'cedar_compiled_server <- cedar_compile_server(server, "server.R")')
  expect_length(nothing_yet, 1L)
  expect_length(read, 1L)
  expect_length(compiled, 1L)
  expect_lt(nothing_yet, read)
  expect_lt(read, compiled)
})
