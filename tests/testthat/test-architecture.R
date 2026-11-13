context("Architecture Guardrails")

test_that("archived forecasting code is not part of main", {
  forecast_files <- r_files_under("R", "cones", "forecast")
  expect_length(forecast_files, 0)

  active_files <- c(
    r_files_under("R"),
    file.path(cedar_base_dir, "global.R"),
    file.path(cedar_base_dir, "server.R"),
    file.path(cedar_base_dir, "ui.R")
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
    file.path(cedar_base_dir, "global.R"),
    file.path(cedar_base_dir, "server.R"),
    file.path(cedar_base_dir, "ui.R")
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
    file.path(cedar_base_dir, "global.R"),
    file.path(cedar_base_dir, "server.R"),
    file.path(cedar_base_dir, "ui.R")
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
  # Every projection file below the modules, so a stage split into its own
  # file is covered without anyone remembering to list it here.
  files <- unlist(lapply(c("R/branches", "R/cones", "R/features"), function(dir) {
    list.files(file.path(cedar_base_dir, dir),
               pattern = "^enrollment-projection.*\\.R$", full.names = TRUE)
  }))
  expect_gte(length(files), 13L)
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
    file.path(cedar_base_dir, "global.R"),
    file.path(cedar_base_dir, "server.R"),
    file.path(cedar_base_dir, "ui.R")
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
    file.path(cedar_base_dir, "server.R")
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

test_that("nothing activates renv at runtime", {
  # CEDAR pins packages with renv.lock and never activates at runtime.
  # scripts/r-environment.R is the only sanctioned setup path, .Rprofile says so,
  # and the Docker image installs the pinned set into the SYSTEM library.
  #
  # parse-data.R called renv::activate() and took production down: inside the
  # container renv/library is empty, so activating repointed .libPaths() at
  # nothing and every library() call after it failed. The tryCatch around it
  # caught nothing, because activate() succeeds -- the failures come later.
  dirs <- c("../../R", "../../scripts")
  offenders <- character()
  for (dir in dirs) {
    if (!dir.exists(dir)) next
    files <- list.files(dir, pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
    files <- files[basename(files) != "r-environment.R"]
    for (file in files) {
      lines <- readLines(file, warn = FALSE)
      # Calls, not prose: a line mentioning it inside a comment is fine.
      code <- sub("#.*$", "", lines)
      hits <- grep("renv::(activate|deactivate|restore|load)\\s*\\(", code, perl = TRUE)
      for (line_no in hits) {
        offenders <- c(offenders, paste0(
          basename(file), ":", line_no, ": ", trimws(lines[[line_no]])
        ))
      }
    }
  }
  if (length(offenders) > 0) {
    fail(paste(
      "renv must not be activated or restored at runtime. Use",
      "scripts/r-environment.R, which is the only file allowed to call it:\n",
      paste(offenders, collapse = "\n")
    ))
  }
  succeed()
})

test_that("every R/lists file declares whether it is platform or institution", {
  files <- list.files("../../R/lists", pattern = "[.]R$", full.names = TRUE)
  offenders <- character()
  for (file in files) {
    first <- readLines(file, n = 1L, warn = FALSE)
    if (!grepl("^# CEDAR-(PLATFORM|INSTITUTION):", first)) {
      offenders <- c(offenders, basename(file))
    }
  }
  if (length(offenders) > 0) {
    fail(paste(
      "R/lists files must open with '# CEDAR-PLATFORM:' or '# CEDAR-INSTITUTION:'",
      "so an adopter knows what to replace:\n",
      paste(offenders, collapse = "\n")
    ))
  }
  succeed()
})

test_that("institution codes stay out of executable platform code", {
  # UNM's campus, college and branch codes belong in R/lists, and platform code
  # may read them through a named constant. It may not contain them: a 16-code
  # F-prefix list hardcoded in transform-to-cedar.R drifted from its counterpart
  # in R/lists and misclassified 23,272 student-term rows before anyone noticed
  # (ISSUES.md I9). This is the check that keeps that from recurring.
  dirs <- c("../../R/trunk", "../../R/branches", "../../R/cones",
            "../../R/features", "../../R/data-parsers")
  # Branch campus codes and the colleges they roll up to. Deliberately narrow:
  # two-letter strings are common, so this looks for the institution's own set
  # appearing as a literal vector, which is what configuration looks like.
  pattern <- '"(GA|LA|TA|VA)"\\s*,\\s*"(GA|LA|TA|VA)"'
  offenders <- character()
  for (dir in dirs) {
    if (!dir.exists(dir)) next
    for (file in list.files(dir, pattern = "[.]R$", full.names = TRUE, recursive = TRUE)) {
      lines <- readLines(file, warn = FALSE)
      hits <- grep(pattern, lines, perl = TRUE)
      for (line_no in hits) {
        if (grepl("INSTITUTION-OK:", paste(
          lines[max(1L, line_no - 3L):line_no], collapse = " "), fixed = TRUE)) next
        offenders <- c(offenders, paste0(
          basename(file), ":", line_no, ": ", trimws(lines[[line_no]])
        ))
      }
    }
  }
  if (length(offenders) > 0) {
    fail(paste(
      "Institution codes appear as literals in platform code. Move them to a",
      "named constant in R/lists and read it here, or mark the site",
      "INSTITUTION-OK: with a reason:\n", paste(offenders, collapse = "\n")
    ))
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
    readLines(file.path(cedar_base_dir, "R", "data-parsers", "transform-to-cedar.R"),
              warn = FALSE),
    collapse = "\n"
  )

  # The class-list dedup's key (dedup_class_list_rows()) keeps campus.
  expect_match(
    transform,
    'keys <- c\\("student_id", "term", "campus", "subject_course"\\)'
  )
  expect_false(grepl("group_by\\(term, crosslist_group\\)", transform))
  expect_false(grepl('by = c\\("term", "crosslist_group"\\)', transform))
})

test_that("the standard gate owns every committed browser suite", {
  runner <- paste(readLines(file.path(cedar_base_dir, "run-tests.sh"), warn = FALSE), collapse = "\n")
  suite_line <- regmatches(runner, regexpr("suites=\\([^)]*\\)", runner, perl = TRUE))
  expect_length(suite_line, 1)

  declared <- sub("^suites=\\(", "", suite_line)
  declared <- sub("\\)$", "", declared)
  declared <- strsplit(trimws(declared), "\\s+")[[1]]
  committed <- sub(
    "\\.test\\.mjs$", "",
    basename(list.files(file.path(cedar_base_dir, "tests", "e2e"),
                        pattern = "\\.test\\.mjs$", full.names = TRUE))
  )

  expect_setequal(declared, committed)
})

test_that("Docker data directory is configured before data paths are resolved", {
  global <- readLines(file.path(cedar_base_dir, "global.R"), warn = FALSE)
  assignment <- grep("^\\s*data_dir\\s*<-", global)[1]
  first_use <- grep("get_cedar_data_path\\(cedar_file_name, data_dir", global)[1]

  expect_false(is.na(assignment))
  expect_false(is.na(first_use))
  expect_lt(assignment, first_use)
})

# ADR-001 step 6: the transform builds every table the app holds; the app and
# the analysis helper load. A build call in either is a startup that computes.
test_that("no loader builds a measure table", {
  builders <- "\\bbuild_(attempts|course_terms|course_flows)\\("
  for (loader in c("global.R", "scripts/cedar-repl.R",
                   "scripts/warm-dept-dashboard-cache.R", "scripts/warm-dept-trends-cache.R")) {
    lines <- readLines(file.path(cedar_base_dir, loader), warn = FALSE)
    code <- sub("#.*$", "", lines)
    expect_false(any(grepl(builders, code)), info = loader)
  }
  transform <- readLines(file.path(cedar_base_dir, "R/data-parsers/transform-to-cedar.R"), warn = FALSE)
  expect_true(any(grepl("build_attempts\\(", transform)))
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

  expect_false(any(file.exists(file.path(cedar_base_dir, retired))))
})

test_that("deploy CI invokes the canonical non-browser gate", {
  workflow <- paste(
    readLines(file.path(cedar_base_dir, ".github", "workflows", "deploy.yml"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(workflow, "./run-tests.sh", fixed = TRUE)
  expect_false(grepl("testthat::test_dir", workflow, fixed = TRUE))
})


# ISSUES.md I5: the section and class-list transforms each had their own level
# rule, and they disagreed -- the DESR rule sent every 4-digit number to
# "lower". Both must call the one classifier.
test_that("both transforms derive course level through course_level_from_number", {
  code <- read_code(file.path(cedar_base_dir, "R/data-parsers/transform-to-cedar.R"))
  calls <- gregexpr("course_level_from_number\\(", code)[[1]]
  expect_equal(sum(calls > 0), 2L,
               info = "transform_sections and transform_students must both use it")
  expect_false(grepl("level\\s*=\\s*(dplyr::)?case_when", code),
               info = "no hand-written level rule may return to the transform")
})


# ---- Ratcheted backlogs: M11 silent fallbacks, M12 global state ----------------
#
# These two tests enforce a rule that already exists in AGENTS.md but had no
# guard: analytical code must not swallow an error into a default, and cones and
# branches must not reach into global state for a table. Each file's allowance
# is today's count. A file that grows fails. A file that shrinks also fails,
# with the instruction to lower its allowance, so the number here is always
# the real backlog and never a stale ceiling. Delete a file's entry when it
# reaches zero.

test_that("silent error fallbacks do not grow, and the backlog shrinks on record (M11)", {
  # AGENTS.md: tryCatch(..., error = function(e) NULL) around a data pipeline
  # is always a bug. Two uses are allowed anywhere: an error shown to the user
  # with showNotification(), and a degenerate statistic returning NA.
  files <- c(
    r_files_under("R"),
    file.path(cedar_base_dir, c("global.R", "server.R", "ui.R"))
  )
  files <- files[!grepl("/R/lists/", files)]
  measured <- architecture_count_by_file(files, function(file) {
    handlers <- architecture_error_handlers(file)
    sum(vapply(handlers, architecture_silent_fallback, logical(1)))
  })
  # Measured 2026-10-16. Lower a number when you fix one; never raise one.
  allowance <- c(
    "R/modules/dept-trends.R" = 1L,
    "R/modules/pathways.R" = 10L,
    "R/modules/regstats.R" = 1L,
    "R/modules/seatfinder.R" = 1L,
    "R/modules/ui-helpers.R" = 1L,
    "R/modules/waitlist.R" = 1L,
    "R/trunk/logging.R" = 7L,
    "server.R" = 8L
  )
  architecture_expect_ratchet(measured, allowance, "silent fallback(s)")
})

test_that("cones and branches do not read global state (M12)", {
  # AGENTS.md: every table a cone needs is a parameter. No data_objects, no
  # exists("cedar_..."), no get() from the global environment. The two guards
  # that are allowed because they exist for standalone sourcing are
  # exists("%||%") and exists("cedar_log_level"). This began as a ratchet over
  # a measured backlog (19 across 5 files); the backlog was cleared on
  # 2026-10-16, so the allowance is empty and any match fails.
  files <- c(r_files_under("R", "cones"), r_files_under("R", "branches"))
  pattern <- paste0(
    "\\bdata_objects\\b|",
    "\\.GlobalEnv|",
    "\\bget\\(\\s*\"cedar_|",
    "\\bexists\\(\\s*\"(?!%\\|\\|%\"|cedar_log_level\")"
  )
  measured <- architecture_count_by_file(files, function(file) {
    lines <- readLines(file, warn = FALSE)
    lines <- lines[!grepl("^\\s*#", lines)]
    sum(grepl(pattern, lines, perl = TRUE))
  })
  architecture_expect_ratchet(measured, integer(0), "global-state read(s)")
})

test_that("units are resolved only by attach_unit() and the lists layer (ADR-001 step 3)", {
  # The invariant that prevents I9: one place reads the mapping files into a
  # unit, so two readers cannot drift apart. attach_unit() in
  # R/branches/dims.R is that place; the lists layer holds the rules it wraps.
  # Everything else reads the attached column. A ratchet over today's
  # backlog, as for M11: each file's allowance is its count, which may only
  # go down. The transform writes no unit since the step's second PR, and
  # builds no lookup from the files since the third; what it still reads from
  # them is a program's pre-major flag.
  files <- c(
    r_files_under("R", "trunk"), r_files_under("R", "branches"), r_files_under("R", "cones"),
    r_files_under("R", "features"), r_files_under("R", "modules"),
    r_files_under("R", "data-parsers"),
    file.path(cedar_base_dir, c("global.R", "server.R"))
  )
  files <- files[!grepl("/R/branches/dims\\.R$", files)]
  pattern <- paste0(
    "resolve_course_units\\(|resolve_program_units\\(|resolve_program_colleges\\(|",
    "\\.confirmed_program_rows\\(|program_pre_major_flags\\(|read_institution_mappings\\(|",
    "\\bsubj_dept_map\\b(?!\\.R)|\\bcedar_institution_files\\b|\\bsubj_to_dept\\b|\\bmajor_to_dept\\b"
  )
  measured <- architecture_count_by_file(files, function(file) {
    lines <- readLines(file, warn = FALSE)
    lines <- lines[!grepl("^\\s*#", lines)]
    sum(grepl(pattern, lines, perl = TRUE))
  })
  # Measured 2026-11-06. Lower a number when you move a reader; never raise one.
  allowance <- c(
    "R/branches/mapping-audit.R" = 1L,
    "R/branches/student-terms.R" = 2L,
    # Reads the files (2) and a program's pre-major flag (1): nothing here
    # resolves a unit.
    "R/data-parsers/transform-to-cedar.R" = 3L,
    "R/features/dept-trends.R" = 4L,
    "R/modules/headcount.R" = 1L,
    "R/trunk/utils.R" = 1L,
    "server.R" = 8L
  )
  architecture_expect_ratchet(measured, allowance, "unit resolution(s) outside attach_unit()")
})

test_that("a test file holds tests, a table is a fixed object, a helper is a tool", {
  # docs/developers/testing.md (Where test code lives). A test file's top level
  # is test_that() blocks. Every table a test reads is a fixed object, built
  # once before any test runs: the designed fixtures, the tables setup.R
  # derives from them, and fixtures/scenario_tables.R. A helper file
  # (tests/testthat/helper-*.R) holds what a test does, never what it reads:
  # functions and constants, and no function there types a table. Attaching a
  # package or sourcing a file is helper-load-functions.R's alone. A definition
  # in a test file reaches that file only, and a library() or source() there
  # stays in effect for every file after it. Not a ratchet: each count is zero.
  dir <- file.path(cedar_base_dir, "tests", "testthat")
  test_files <- list.files(dir, "^test-.*\\.R$", full.names = TRUE)
  helper_files <- setdiff(list.files(dir, "^helper-.*\\.R$", full.names = TRUE),
                          file.path(dir, "helper-load-functions.R"))
  expect_gt(length(test_files), 80L)
  expect_gt(length(helper_files), 30L)
  top_level <- function(files) do.call(rbind, lapply(files, architecture_top_level))
  describe <- function(rows) paste(sprintf("%s:%d %s", rows$file, rows$line, rows$what), collapse = "\n")

  in_tests <- top_level(test_files)
  stray <- in_tests[in_tests$kind != "test", ]
  expect(nrow(stray) == 0L, paste0(
    "outside a test_that() block; a table goes in fixtures/scenario_tables.R, ",
    "a tool in tests/testthat/helper-<topic>.R:\n", describe(stray)))

  in_helpers <- top_level(helper_files)
  stray <- in_helpers[in_helpers$kind != "definition", ]
  expect(nrow(stray) == 0L, paste0(
    "a helper file runs something at load; define a function, or load it in ",
    "helper-load-functions.R:\n", describe(stray)))

  # A function with no argument returns the same thing every call: fixed data
  # written as a function. The exceptions do something and are listed by name.
  no_args <- in_helpers[in_helpers$n_args %in% 0L, ]
  stray <- no_args[!no_args$what %in% names(helper_actions_without_arguments), ]
  expect(nrow(stray) == 0L, paste0(
    "a helper function with no argument is a fixed table; make it an object in ",
    "fixtures/scenario_tables.R:\n", describe(stray)))
  gone <- setdiff(names(helper_actions_without_arguments), no_args$what)
  expect(length(gone) == 0L, paste0(
    "listed in helper_actions_without_arguments but no longer a helper function ",
    "with no argument; remove from the list: ", paste(gone, collapse = ", ")))

  # A table typed inside a helper function is data chosen at call time, and a
  # table held by a helper object is a fixture in the wrong file.
  typed <- in_helpers[!is.na(in_helpers$types_table) & nzchar(in_helpers$types_table), ]
  stray <- typed[!typed$what %in% names(helper_functions_typing_a_table), ]
  expect(nrow(stray) == 0L, paste0(
    "a helper function types a table (", paste(architecture_table_constructors, collapse = ", "),
    "); make the table an object in fixtures/scenario_tables.R and state the ",
    "change in the test:\n", describe(stray)))
  gone <- setdiff(names(helper_functions_typing_a_table), typed$what)
  expect(length(gone) == 0L, paste0(
    "listed in helper_functions_typing_a_table but no longer a helper function ",
    "that types one; remove from the list: ", paste(gone, collapse = ", ")))
  objects <- in_helpers[in_helpers$kind == "definition" & is.na(in_helpers$n_args), ]
  held <- vapply(objects$what, function(name) {
    architecture_holds_table(get0(name, inherits = TRUE))
  }, logical(1))
  stray <- objects[held, ]
  expect(nrow(stray) == 0L, paste0(
    "a helper file holds a table; move it to fixtures/scenario_tables.R:\n", describe(stray)))

  scenario <- architecture_top_level(file.path(dir, "fixtures", "scenario_tables.R"))
  expect_gt(nrow(scenario), 50L)
  stray <- scenario[scenario$kind != "definition" | !is.na(scenario$n_args), ]
  expect(nrow(stray) == 0L, paste0(
    "fixtures/scenario_tables.R holds fixed objects only; a function is a helper:\n",
    describe(stray)))
})
