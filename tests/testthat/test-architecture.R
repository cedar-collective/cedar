context("Architecture Guardrails")

project_root <- normalizePath(file.path(getwd(), "../.."))

r_files_under <- function(...) {
  path <- file.path(project_root, ...)
  list.files(path, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
}

read_code <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lines <- lines[!grepl("^\\s*#", lines)]
  paste(lines, collapse = "\n")
}

relative_path <- function(path) {
  sub(paste0("^", normalizePath(project_root), "/"), "", normalizePath(path))
}

extract_function_names <- function(file) {
  code <- read_code(file)
  hits <- regmatches(
    code,
    gregexpr("\\b[A-Za-z.][A-Za-z0-9_.]*\\s*<-\\s*function\\s*\\(", code, perl = TRUE)
  )[[1]]
  if (identical(hits, character(0)) || hits[1] == -1) {
    return(character())
  }
  sub("\\s*<-.*$", "", hits)
}

test_that("archived forecasting code is not part of main", {
  forecast_files <- r_files_under("R", "cones", "forecast")
  expect_length(forecast_files, 0)

  active_files <- c(
    r_files_under("R"),
    file.path(project_root, "global.R"),
    file.path(project_root, "server.R"),
    file.path(project_root, "ui.R")
  )
  active_text <- paste(vapply(active_files, read_code, character(1)), collapse = "\n")

  expect_false(grepl("cones/forecast", active_text, fixed = TRUE))
  expect_false(grepl("calc_forecast_accuracy\\s*\\(", active_text, perl = TRUE))
  expect_false(grepl("\\bforecast\\s*\\(", active_text, perl = TRUE))
  expect_false(grepl("data_objects\\[\\[\"forecasts\"\\]\\]", active_text, perl = TRUE))
})

test_that("active code does not call retired gradebook APIs", {
  active_files <- c(
    r_files_under("R"),
    file.path(project_root, "global.R"),
    file.path(project_root, "server.R"),
    file.path(project_root, "ui.R")
  )
  active_text <- paste(vapply(active_files, read_code, character(1)), collapse = "\n")

  retired_calls <- c("get_grades", "calculate_dfw", "plot_grades_for_course_report")
  for (fn in retired_calls) {
    expect_false(
      grepl(paste0("\\b", fn, "\\s*\\("), active_text, perl = TRUE),
      info = paste("Retired gradebook call still present:", fn)
    )
  }
})

test_that("registration status literals stay at the parsing/constants boundary", {
  files <- r_files_under("R")
  allowed <- c(
    "R/lists/status_codes.R",
    "R/data-parsers/class-list-waitlists.R",
    "R/data-parsers/parse-data.R"
  )

  status_literal_pattern <- '"(RE|RS|RR|WL|DR|DG|DW|DD)"'
  offenders <- character()
  for (file in files) {
    rel <- relative_path(file)
    if (rel %in% allowed) next
    if (grepl(status_literal_pattern, read_code(file), perl = TRUE)) {
      offenders <- c(offenders, rel)
    }
  }

  if (length(offenders) > 0) {
    fail(paste("Inline status-code literals found outside constants/parsers:\n", paste(offenders, collapse = "\n")))
  }
  succeed()
})

test_that("runtime code does not access legacy uppercase data columns", {
  files <- c(
    r_files_under("R"),
    file.path(project_root, "global.R"),
    file.path(project_root, "server.R"),
    file.path(project_root, "ui.R")
  )
  files <- files[!grepl("/R/data-parsers/", normalizePath(files), fixed = TRUE)]

  patterns <- c(
    "\\$[A-Z][A-Z0-9_]*\\b",
    "\\[\\[\\s*['\"][A-Z][A-Z0-9_]*['\"]\\s*\\]\\]",
    "\\[\\s*,\\s*['\"][A-Z][A-Z0-9_]*['\"]\\s*\\]"
  )

  offenders <- character()
  for (file in files) {
    code <- read_code(file)
    if (any(vapply(patterns, grepl, logical(1), x = code, perl = TRUE))) {
      offenders <- c(offenders, relative_path(file))
    }
  }

  if (length(offenders) > 0) {
    fail(paste("Legacy uppercase column access found in runtime code:\n", paste(offenders, collapse = "\n")))
  }
  succeed()
})

test_that("cones do not directly call other cones", {
  cone_files <- r_files_under("R", "cones")
  definitions <- stats::setNames(lapply(cone_files, extract_function_names), cone_files)
  offenders <- character()

  for (file in cone_files) {
    code <- read_code(file)
    own_defs <- definitions[[file]]
    other_defs <- unlist(definitions[names(definitions) != file], use.names = FALSE)
    other_defs <- setdiff(unique(other_defs), own_defs)

    calls <- other_defs[vapply(other_defs, function(fn) {
      escaped <- gsub(".", "\\\\.", fn, fixed = TRUE)
      grepl(paste0("\\b", escaped, "\\s*\\("), code, perl = TRUE)
    }, logical(1))]

    if (length(calls) > 0) {
      offenders <- c(offenders, paste0(relative_path(file), ": ", paste(sort(unique(calls)), collapse = ", ")))
    }
  }

  if (length(offenders) > 0) {
    fail(paste("Cone-to-cone calls found:\n", paste(offenders, collapse = "\n")))
  }
  succeed()
})

test_that("projection computation stays independent of Shiny and global data", {
  files <- file.path(
    project_root,
    c(
      "R/branches/enrollment-projections.R",
      "R/cones/enrollment-projections.R",
      "R/features/enrollment-projections.R"
    )
  )
  code <- paste(vapply(files, read_code, character(1)), collapse = "\n")

  forbidden <- c(
    "\\binput\\$", "\\boutput\\$", "\\bsession\\$",
    "\\bdata_objects\\b", "\\.GlobalEnv", "\\bcedar_students\\b",
    "\\bcedar_sections\\b", "\\bcedar_programs\\b"
  )
  for (pattern in forbidden) {
    expect_false(
      grepl(pattern, code, perl = TRUE),
      info = paste("Projection computation contains forbidden dependency:", pattern)
    )
  }
})

test_that("runtime code uses centralized ColorBrewer access", {
  files <- c(
    r_files_under("R"),
    file.path(project_root, "global.R"),
    file.path(project_root, "server.R"),
    file.path(project_root, "ui.R")
  )
  allowed <- "R/trunk/utils.R"

  offenders <- character()
  for (file in files) {
    rel <- relative_path(file)
    if (rel == allowed) next
    if (grepl("RColorBrewer::brewer\\.pal\\s*\\(", read_code(file), perl = TRUE)) {
      offenders <- c(offenders, rel)
    }
  }

  if (length(offenders) > 0) {
    fail(paste("Direct RColorBrewer calls found outside palette helpers:\n", paste(offenders, collapse = "\n")))
  }
  succeed()
})

test_that("department filter options use dept_code", {
  files <- c(
    r_files_under("R"),
    file.path(project_root, "server.R")
  )

  patterns <- c(
    "opt\\$dept\\b",
    "opt\\[\\[\\s*['\"]dept['\"]\\s*\\]\\]"
  )

  offenders <- character()
  for (file in files) {
    code <- read_code(file)
    if (any(vapply(patterns, grepl, logical(1), x = code, perl = TRUE))) {
      offenders <- c(offenders, relative_path(file))
    }
  }

  if (length(offenders) > 0) {
    fail(paste("Department filter options should use opt$dept_code, not opt$dept:\n", paste(offenders, collapse = "\n")))
  }
  succeed()
})

test_that("literal course groupings include campus or declare a curriculum rollup", {
  files <- r_files_under("R")
  operation <- "\\b(group_by|count|distinct)\\s*\\([^)]*subject_course"
  offenders <- character()

  for (file in files) {
    lines <- readLines(file, warn = FALSE)
    hits <- grep(operation, lines, perl = TRUE)
    for (line_no in hits) {
      if (grepl("campus", lines[[line_no]], fixed = TRUE)) next
      lookback <- lines[max(1L, line_no - 8L):line_no]
      if (any(grepl("CAMPUS_ROLLUP:", lookback, fixed = TRUE))) next
      offenders <- c(
        offenders,
        paste0(relative_path(file), ":", line_no, ": ", trimws(lines[[line_no]]))
      )
    }
  }

  if (length(offenders) > 0) {
    fail(paste(
      "Literal subject_course grouping omits campus without a CAMPUS_ROLLUP explanation:\n",
      paste(offenders, collapse = "\n")
    ))
  }
  succeed()
})

test_that("literal course group_cols vectors include campus or declare a rollup", {
  files <- r_files_under("R")
  operation <- "group_cols\\s*=\\s*c\\([^)]*subject_course"
  offenders <- character()

  for (file in files) {
    lines <- readLines(file, warn = FALSE)
    hits <- grep(operation, lines, perl = TRUE)
    for (line_no in hits) {
      if (grepl("campus", lines[[line_no]], fixed = TRUE)) next
      lookback <- lines[max(1L, line_no - 8L):line_no]
      if (any(grepl("CAMPUS_ROLLUP:", lookback, fixed = TRUE))) next
      offenders <- c(
        offenders,
        paste0(relative_path(file), ":", line_no, ": ", trimws(lines[[line_no]]))
      )
    }
  }

  if (length(offenders) > 0) {
    fail(paste(
      "Literal course group_cols omits campus without a CAMPUS_ROLLUP explanation:\n",
      paste(offenders, collapse = "\n")
    ))
  }
  succeed()
})

test_that("transformed delivery keys retain campus", {
  transform <- paste(
    readLines(file.path(project_root, "R", "data-parsers", "transform-to-cedar.R"),
              warn = FALSE),
    collapse = "\n"
  )

  expect_match(
    transform,
    "distinct\\(student_id, term, campus, subject_course, \\.keep_all = TRUE\\)"
  )
  expect_false(grepl("group_by\\(term, crosslist_group\\)", transform))
  expect_false(grepl('by = c\\("term", "crosslist_group"\\)', transform))
})

test_that("the standard gate owns every committed browser suite", {
  runner <- paste(readLines(file.path(project_root, "run-tests.sh"), warn = FALSE), collapse = "\n")
  suite_line <- regmatches(runner, regexpr("suites=\\([^)]*\\)", runner, perl = TRUE))
  expect_length(suite_line, 1)

  declared <- sub("^suites=\\(", "", suite_line)
  declared <- sub("\\)$", "", declared)
  declared <- strsplit(trimws(declared), "\\s+")[[1]]
  committed <- sub(
    "\\.test\\.mjs$", "",
    basename(list.files(file.path(project_root, "tests", "e2e"),
                        pattern = "\\.test\\.mjs$", full.names = TRUE))
  )

  expect_setequal(declared, committed)
})

test_that("Docker data directory is configured before data paths are resolved", {
  global <- readLines(file.path(project_root, "global.R"), warn = FALSE)
  assignment <- grep("^\\s*data_dir\\s*<-", global)[1]
  first_use <- grep("get_cedar_data_path\\(cedar_file_name, data_dir", global)[1]

  expect_false(is.na(assignment))
  expect_false(is.na(first_use))
  expect_lt(assignment, first_use)
})

test_that("legacy custom test runners stay retired", {
  retired <- c(
    "tests/run-tests.sh",
    "tests/testthat.R",
    "tests/test-docker-shiny.sh",
    "tests/test-shiny-browser.py",
    "tests/test-course-report-standalone.R",
    "tests/test-credit-hours-standalone.R",
    "tests/test-crosslist-sample.R",
    "tests/test-dept-dashboard-standalone.R"
  )

  expect_false(any(file.exists(file.path(project_root, retired))))
})

test_that("deploy CI invokes the canonical non-browser gate", {
  workflow <- paste(
    readLines(file.path(project_root, ".github", "workflows", "deploy.yml"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(workflow, "./run-tests.sh", fixed = TRUE)
  expect_false(grepl("testthat::test_dir", workflow, fixed = TRUE))
})
