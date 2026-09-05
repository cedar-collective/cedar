# These are workflow/runner input contracts, not institutional-data fixtures.
project_root <- normalizePath(file.path(getwd(), "../.."))
test_that("PR checks are read-only, secret-free, and independent of deployment", {
  path <- file.path(project_root, ".github", "workflows", "pr-checks.yml")
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
  expect_identical(job$env$CEDAR_URL, "http://127.0.0.1:3839/")
})

test_that("PR checks run the full standard gate against an isolated synthetic app", {
  workflow <- yaml::read_yaml(file.path(project_root, ".github", "workflows", "pr-checks.yml"))
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
  runner <- file.path(project_root, "run-tests.sh")
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
  runner <- file.path(project_root, "run-tests.sh")
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
