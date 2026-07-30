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
