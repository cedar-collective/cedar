#!/usr/bin/env Rscript
# CEDAR: does a test catch the bug it was written for?
#
#   Rscript --vanilla scripts/check-test-catches.R <breaks.yml> [--timeout <seconds>]
#
# A test written beside a fix often passes for the wrong reason: its fixture
# is too simple to express the bug, or it asserts something the bug never
# touched. The proof is to put the bug back and watch the test fail. This
# script does that for a list of breaks, each one piece of text in one file:
#
#   - name: the scope joined on the student alone
#     file: R/cones/course-band-dfw.R
#     old: 'by = c("student_id", "term")'
#     new: 'by = "student_id"'
#     tests: [test-course-band-dfw.R]
#
# `old` must be in the file exactly once. `tests` are files in tests/testthat.
# An entry may carry its own `timeout` in seconds.
#
# THE CHECKOUT IS NEVER EDITED. The script copies the tree to a temporary
# directory (the files git tracks plus the new ones it does not ignore; every
# file where there is no git), runs the named tests there as the tree stands
# (a test that already fails proves nothing), then for each break writes the
# broken file into the copy, runs the tests in a new R process under a time
# limit, and puts the copy's file back. So nothing is left to restore when a
# run is interrupted, a break never reaches a container that mounts the
# checkout, and a break that starts something long is stopped at the limit.
#
# A break is CAUGHT when a test fails or errors with it in place. It is not
# caught when the tests pass, when they run past the time limit, or when the
# test file cannot run at all (a break that stops the suite's set-up shows no
# test holding it).
#
# Exit status: 0 every break caught; 1 at least one not caught; 2 the breaks
# file cannot be used, or a named test fails as the tree stands.
#
# The breaks file is a working note, not part of the repository: keep it in a
# scratch directory and list the breaks in the pull request.

`%||%` <- function(a, b) if (is.null(a)) b else a

catches_stop <- function(...) {
  message("check-test-catches: ", ...)
  quit(save = "no", status = 2L)
}

catches_script_root <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) != 1L) catches_stop("run this script with Rscript")
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), ".."))
}

catches_arguments <- function(args) {
  out <- list(breaks = NULL, timeout = 300L, root = NULL)
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--timeout", "--root")) {
      if (i == length(args)) catches_stop(arg, " needs a value")
      out[[sub("^--", "", arg)]] <- args[[i + 1L]]
      i <- i + 2L
    } else if (startsWith(arg, "--")) {
      catches_stop("unknown option ", arg)
    } else {
      if (!is.null(out$breaks)) catches_stop("one breaks file at a time")
      out$breaks <- arg
      i <- i + 1L
    }
  }
  if (is.null(out$breaks)) {
    catches_stop("usage: Rscript --vanilla scripts/check-test-catches.R <breaks.yml> [--timeout <seconds>]")
  }
  out$timeout <- suppressWarnings(as.integer(out$timeout))
  if (is.na(out$timeout) || out$timeout < 1L) catches_stop("--timeout is a whole number of seconds")
  out
}

catches_read_breaks <- function(path, root, default_timeout) {
  if (!file.exists(path)) catches_stop("no breaks file at ", path)
  breaks <- yaml::read_yaml(path)
  if (!is.list(breaks) || length(breaks) == 0L || !is.null(names(breaks))) {
    catches_stop(path, " is not a list of breaks (each entry starts with '- name:')")
  }
  lapply(seq_along(breaks), function(i) {
    entry <- breaks[[i]]
    where <- sprintf("break %d", i)
    if (!is.list(entry)) catches_stop(where, " is not an entry with name, file, old, new and tests")
    for (field in c("name", "file", "old", "new")) {
      value <- entry[[field]]
      if (!is.character(value) || length(value) != 1L || is.na(value)) {
        catches_stop(where, " needs `", field, "` as one piece of text")
      }
    }
    where <- sprintf("break %d (%s)", i, entry$name)
    tests <- unlist(entry$tests)
    if (!is.character(tests) || length(tests) == 0L) catches_stop(where, " names no test file in `tests`")
    tests <- file.path("tests", "testthat", basename(tests))
    absent <- tests[!file.exists(file.path(root, tests))]
    if (length(absent) > 0L) catches_stop(where, ": no test file ", paste(absent, collapse = ", "))
    if (!nzchar(entry$old)) catches_stop(where, ": `old` is empty")
    if (identical(entry$old, entry$new)) catches_stop(where, ": `old` and `new` are the same text")
    if (!file.exists(file.path(root, entry$file))) catches_stop(where, ": no file ", entry$file)
    timeout <- suppressWarnings(as.integer(entry$timeout %||% default_timeout))
    if (is.na(timeout) || timeout < 1L) catches_stop(where, ": `timeout` is a whole number of seconds")
    found <- catches_count(catches_read(file.path(root, entry$file)), entry$old)
    if (found == 0L) {
      catches_stop(where, ": `old` is not in ", entry$file,
                   if (endsWith(entry$old, "\n")) " (a `|` block ends with a line break: write `|-`)")
    }
    if (found > 1L) {
      catches_stop(where, ": `old` is in ", entry$file, " ", found,
                   " times; write enough of the line that it is there once")
    }
    list(number = i, name = entry$name, file = entry$file, old = entry$old, new = entry$new,
         tests = tests, timeout = timeout)
  })
}

# A file as one string of bytes, so a replacement changes nothing else in it.
catches_read <- function(path) readChar(path, file.info(path)$size, useBytes = TRUE)

catches_count <- function(text, old) {
  at <- gregexpr(old, text, fixed = TRUE, useBytes = TRUE)[[1]]
  sum(at > 0L)
}

catches_write_broken <- function(from, to, old, new) {
  broken <- sub(old, new, catches_read(from), fixed = TRUE, useBytes = TRUE)
  writeChar(broken, to, eos = NULL, useBytes = TRUE)
}

# The files that make up the tree a test reads. In a checkout: what git tracks
# and the new files it does not ignore, so data, output and installed packages
# stay behind. Without git (the app image): everything that is there.
catches_tree_files <- function(root) {
  if (!file.exists(file.path(root, ".git"))) {
    return(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  }
  listed <- suppressWarnings(system2("git", c("-C", shQuote(root), "ls-files", "-co", "--exclude-standard"),
                                     stdout = TRUE, stderr = FALSE))
  if (!is.null(attr(listed, "status")) || length(listed) == 0L) {
    catches_stop("git could not list the files of ", root)
  }
  listed[file.exists(file.path(root, listed))]
}

catches_copy_tree <- function(root, to) {
  files <- catches_tree_files(root)
  for (dir in unique(dirname(files))) {
    dir.create(file.path(to, dir), recursive = TRUE, showWarnings = FALSE)
    here <- files[dirname(files) == dir]
    copied <- file.copy(file.path(root, here), file.path(to, dir), copy.date = TRUE)
    if (!all(copied)) catches_stop("could not copy ", paste(here[!copied], collapse = ", "))
  }
  length(files)
}

# What a run that stopped said: its error, without the backtrace under it.
catches_error_lines <- function(said) {
  said <- said[nzchar(trimws(said))]
  start <- grep("^Error", said)[1]
  if (is.na(start)) return(utils::tail(said, 6L))
  end <- grep("^Backtrace:", said)
  end <- end[end > start][1]
  said[start:min(if (is.na(end)) length(said) else end - 1L, start + 7L)]
}

# One test file in a new R process, as ./run-tests.sh runs R: --vanilla, from
# the root of the tree. A list: `outcome` is "ran", "timed_out" or "stopped",
# and `limit` is the time limit the run had.
catches_run_test <- function(tree, test, timeout) {
  results <- tempfile("catches-results-", fileext = ".rds")
  log <- tempfile("catches-log-", fileext = ".txt")
  on.exit(unlink(c(results, log)), add = TRUE)
  code <- sprintf(paste0(
    'res <- as.data.frame(testthat::test_file(%s, reporter = "silent", stop_on_failure = FALSE)); ',
    'saveRDS(res[c("test", "failed", "error")], %s)'), deparse(test), deparse(results))
  old_wd <- setwd(tree)
  on.exit(setwd(old_wd), add = TRUE)
  status <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", shQuote(code)),
                                     stdout = log, stderr = log, timeout = timeout))
  if (identical(status, 124L)) return(list(outcome = "timed_out", limit = timeout))
  if (!file.exists(results)) {
    return(list(outcome = "stopped", limit = timeout,
                said = catches_error_lines(readLines(log, warn = FALSE))))
  }
  res <- readRDS(results)
  list(outcome = "ran", limit = timeout, tests = nrow(res),
       failing = unique(res$test[res$failed > 0L | res$error]))
}

catches_plural <- function(n, one, many = paste0(one, "s")) sprintf("%d %s", n, if (n == 1L) one else many)

catches_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opt <- catches_arguments(args)
  root <- normalizePath(opt$root %||% catches_script_root(), mustWork = FALSE)
  if (!dir.exists(file.path(root, "tests", "testthat"))) catches_stop("no tests/testthat under ", root)
  breaks <- catches_read_breaks(opt$breaks, root, opt$timeout)
  tests <- unique(unlist(lapply(breaks, `[[`, "tests")))

  tree <- tempfile("check-test-catches-")
  dir.create(tree)
  on.exit(unlink(tree, recursive = TRUE), add = TRUE)
  catches_copy_tree(root, tree)
  cat(sprintf("%s against %s, in a copy of the tree. The checkout is not edited.\n\n",
              catches_plural(length(breaks), "break"), catches_plural(length(tests), "test file")))

  for (test in tests) {
    as_is <- catches_run_test(tree, test, opt$timeout)
    if (!identical(as_is$outcome, "ran")) {
      catches_stop(basename(test), " does not run as the tree stands",
                   if (identical(as_is$outcome, "timed_out")) sprintf(" (past %d s)", as_is$limit),
                   if (length(as_is$said) > 0L) paste0(":\n  ", paste(as_is$said, collapse = "\n  ")))
    }
    if (length(as_is$failing) > 0L) {
      catches_stop(basename(test), " fails as the tree stands, so a failure under a break proves nothing:\n  ",
                   paste(as_is$failing, collapse = "\n  "))
    }
    cat(sprintf("As the tree stands: %s passes (%s).\n", basename(test), catches_plural(as_is$tests, "test")))
  }

  caught <- logical(length(breaks))
  for (i in seq_along(breaks)) {
    entry <- breaks[[i]]
    cat(sprintf("\n%d. %s  [%s]\n", entry$number, entry$name, entry$file))
    catches_write_broken(file.path(root, entry$file), file.path(tree, entry$file), entry$old, entry$new)
    for (test in entry$tests) {
      run <- catches_run_test(tree, test, entry$timeout)
      name <- basename(test)
      if (identical(run$outcome, "timed_out")) {
        cat(sprintf("   TIMED OUT: %s ran past %d s with the break in place. That is not a catch.\n",
                    name, run$limit))
      } else if (identical(run$outcome, "stopped")) {
        cat(sprintf("   STOPPED: %s could not run with the break in place, so no test is shown to hold it.\n", name))
        if (length(run$said) > 0L) cat(paste0("     | ", run$said, "\n"), sep = "")
      } else if (length(run$failing) == 0L) {
        cat(sprintf("   NOT CAUGHT: %s passes with the break in place.\n", name))
      } else {
        caught[[i]] <- TRUE
        cat(sprintf("   CAUGHT by %s:\n", name))
        cat(paste0("     ", run$failing, "\n"), sep = "")
      }
    }
    file.copy(file.path(root, entry$file), file.path(tree, entry$file), overwrite = TRUE, copy.date = TRUE)
  }

  cat(sprintf("\n%d of %s caught.", sum(caught), catches_plural(length(breaks), "break")))
  if (!all(caught)) cat(" Not caught: ", paste(which(!caught), collapse = ", "), ".", sep = "")
  cat("\n")
  quit(save = "no", status = if (all(caught)) 0L else 1L)
}

catches_main()
