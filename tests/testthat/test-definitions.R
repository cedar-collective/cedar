context("Shared definition records")

test_that("the shipped registry is valid and implementation references resolve", {
  expect_no_error(validate_definition_registry(CEDAR_DEFINITIONS))
  for (definition in CEDAR_DEFINITIONS$definitions) {
    for (record in definition$versions) {
      # Historical records retain their original paths/names when a later
      # implementation is renamed or retired. Only current references must
      # resolve in this checkout; schema validation above covers every version.
      if (!identical(record$version, definition$current_version)) next
      for (source in record$implementation) {
        path <- file.path(cedar_base_dir, source$file)
        expect_true(file.exists(path), info = source$file)
        code <- paste(readLines(path, warn = FALSE), collapse = "\n")
        for (fn in source$functions) {
          expect_true(exists(fn, mode = "function"), info = fn)
          expect_match(code, paste0(fn, "\\s*<-\\s*function\\("), info = source$file)
        }
      }
      guide <- sub("#.*$", "", record$guide)
      expect_true(file.exists(file.path(cedar_base_dir, "docs", paste0(guide, ".md"))),
                  info = record$guide)
    }
  }
})

test_that("version lookup stays exact after a new version is selected", {
  registry <- CEDAR_DEFINITIONS
  original <- cedar_definition("registered", registry = registry)
  # Metadata input-contract fixture; no student/domain data are invented here.
  next_record <- registry$definitions[[1]]$versions[[1]]
  next_record$version <- "2.0.0"
  next_record$summary <- "A revised definition for this lookup test."
  registry$definitions[[1]]$versions[[2]] <- next_record
  registry$definitions[[1]]$current_version <- "2.0.0"

  expect_no_error(validate_definition_registry(registry))
  expect_identical(cedar_definition("registered", "1.0.0", registry), original)
  expect_identical(cedar_definition("registered", registry = registry)$summary, next_record$summary)
  expect_identical(cedar_definition("registered", registry = registry)$anchor, "registered-v2-0-0")
  expect_error(cedar_definition("registered", "9.0.0", registry), "Unknown definition version")
  expect_error(cedar_definition("unknown", registry = registry), "Unknown definition id")
})

test_that("malformed records cannot silently load", {
  expect_error(read_definition_registry(tempfile()), "not found")
  registry <- CEDAR_DEFINITIONS
  registry$schema_version <- 99L
  expect_error(validate_definition_registry(registry), "unsupported schema")
  registry <- CEDAR_DEFINITIONS
  registry$definitions[[1]]$versions[[1]]$denominator <- NULL
  expect_error(validate_definition_registry(registry), "required fields")
  registry <- CEDAR_DEFINITIONS
  registry$definitions[[1]]$versions[[2]] <- registry$definitions[[1]]$versions[[1]]
  expect_error(validate_definition_registry(registry), "duplicate versions")
  registry <- CEDAR_DEFINITIONS
  registry$definitions[[2]]$id <- registry$definitions[[1]]$id
  expect_error(validate_definition_registry(registry), "duplicate definition ids")
  registry <- CEDAR_DEFINITIONS
  registry$definitions[[1]]$current_version <- "9.0.0"
  expect_error(validate_definition_registry(registry), "current_version does not exist")
})

test_that("definition text survives a non-UTF-8 process locale", {
  old_locale <- Sys.getlocale("LC_CTYPE")
  on.exit(suppressWarnings(Sys.setlocale("LC_CTYPE", old_locale)), add = TRUE)
  expect_true(nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))))
  registry <- read_definition_registry(file.path(cedar_base_dir, "docs/_data/definitions.yml"))
  expect_identical(registry, CEDAR_DEFINITIONS)
})

test_that("user-guide includes select existing shared definitions", {
  files <- list.files(file.path(cedar_base_dir, "docs", "users"), "[.]md$", full.names = TRUE)
  content <- paste(vapply(files, function(file) paste(readLines(file, warn = FALSE), collapse = "\n"),
                          character(1)), collapse = "\n")
  pattern <- 'include definition-summary.html id="([a-z-]+)"'
  includes <- regmatches(content, gregexpr(pattern, content))[[1]]
  expect_gt(length(includes), 0)
  for (item in includes) {
    expect_no_error(cedar_definition(sub(pattern, "\\1", item)))
  }
})

test_that("data guide uses shared enrollment definitions without stale census claims", {
  understanding <- paste(readLines(
    file.path(cedar_base_dir, "docs/users/understanding-data.md"), warn = FALSE
  ), collapse = "\n")
  enrollment <- paste(readLines(
    file.path(cedar_base_dir, "docs/users/enrollment-tab.md"), warn = FALSE
  ), collapse = "\n")
  dashboard <- paste(readLines(
    file.path(cedar_base_dir, "docs/users/dept-dashboard.md"), warn = FALSE
  ), collapse = "\n")

  for (id in c("desr-enrollment", "registered", "census-enrollment")) {
    expect_match(
      understanding,
      paste0('include definition-summary.html id="', id, '"'),
      fixed = TRUE
    )
    expect_match(
      enrollment,
      paste0('include definition-summary.html id="', id, '"'),
      fixed = TRUE
    )
  }
  expect_false(grepl("CEDAR uses nightly snapshots", understanding, fixed = TRUE))
  expect_false(grepl("15th day of the semester", understanding, fixed = TRUE))
  expect_false(grepl("typically updated nightly", understanding, fixed = TRUE))
  expect_false(grepl("typically updated nightly", enrollment, fixed = TRUE))
  expect_false(grepl("Students retained through census", enrollment, fixed = TRUE))
  expect_false(grepl("registrar-authoritative signal", enrollment, fixed = TRUE))
  expect_match(enrollment, "course-campus-college-term", fixed = TRUE)
  expect_match(enrollment, "do not change Classlist", fixed = TRUE)
  expect_false(grepl("DW/DG grades", dashboard, fixed = TRUE))
  expect_match(dashboard, "DG/DW registration-status rows", fixed = TRUE)
  expect_match(understanding, "census1` and `census2` are dates, not stored enrollment counts",
               fixed = TRUE)
})

test_that("app explanations render the registry and exact-version docs links", {
  suppressPackageStartupMessages({library(shiny); library(bslib); library(reactable)})
  load_funcs(cedar_base_dir, modules = TRUE)
  for (definition in CEDAR_DEFINITIONS$definitions) {
    record <- cedar_definition(definition$id)
    html <- as.character(cedar_definition_note(definition$id))
    expect_match(html, htmltools::htmlEscape(record$summary), fixed = TRUE)
    expect_match(html, htmltools::htmlEscape(record$exclusions), fixed = TRUE)
    expect_match(html, paste0('data-definition-version="', record$version, '"'), fixed = TRUE)
    expect_match(html, paste0('href="https://cedarplatform.org/users/definitions#', record$anchor, '"'), fixed = TRUE)
  }

  html <- as.character(pathwaysUI("pathways", campus_choices = c("ABQ", "EA")))
  expect_false(grepl('data-value="Methodology"', html, fixed = TRUE))
  expect_match(html, 'data-value="Major Changes"', fixed = TRUE)
  expect_match(html, 'data-definition-id="course-timing"', fixed = TRUE)
  expect_match(html, 'data-definition-id="roadblocks"', fixed = TRUE)

  gen_ed_html <- as.character(genEdExploreUI(
    "gen_ed_definition_test",
    gen_ed_assoc_sections,
    sort(unique(gen_ed_assoc_sections$department)),
    current_term = max(gen_ed_assoc_sections$term, na.rm = TRUE),
    default_term = max(gen_ed_assoc_sections$term, na.rm = TRUE)
  ))
  expect_match(gen_ed_html, 'data-definition-id="dfw"', fixed = TRUE)
  expect_match(gen_ed_html,
               paste0('data-definition-version="', cedar_definition("dfw")$version, '"'),
               fixed = TRUE)

  dept_gen_ed_html <- as.character(deptProfileGenEdUI("dept_gen_ed_definition_test"))
  expect_match(dept_gen_ed_html, 'data-definition-id="dfw"', fixed = TRUE)
})

test_that("Course Dynamics enrollment prose comes from shared definitions", {
  course_ui <- paste(readLines(file.path(cedar_base_dir, "ui.R"), warn = FALSE),
                     collapse = "\n")

  expect_match(course_ui, 'cedar_definition_summary("registered")', fixed = TRUE)
  expect_match(course_ui, 'cedar_definition_summary("census-enrollment")', fixed = TRUE)
  expect_match(
    course_ui,
    'lapply(c("registered", "census-enrollment"), cedar_definition_note)',
    fixed = TRUE
  )
  expect_false(grepl(
    'tags$li(tags$b("Current enrollment")', course_ui, fixed = TRUE
  ))
  expect_false(grepl(
    'tags$li(tags$b("Census enrollment")', course_ui, fixed = TRUE
  ))
})

test_that("Enrollment page separates DESR display controls from Classlist counts", {
  ui_source <- paste(readLines(file.path(cedar_base_dir, "ui.R"), warn = FALSE),
                     collapse = "\n")
  server_source <- paste(readLines(file.path(cedar_base_dir, "server.R"), warn = FALSE),
                         collapse = "\n")

  expect_match(ui_source, 'cedar_definition_panel("desr-enrollment"', fixed = TRUE)
  expect_match(
    ui_source,
    'c("registered", "census-enrollment")',
    fixed = TRUE
  )
  expect_match(ui_source, 'numericInput("enrl_min", "DESR Min"', fixed = TRUE)
  expect_match(server_source, 'name = "Ever Registered Proxy"', fixed = TRUE)
  expect_match(server_source, 'name = "Census Estimate"', fixed = TRUE)
  expect_match(server_source, 'name = "Registered at Extract"', fixed = TRUE)
  expect_false(grepl("one row per scheduled section", ui_source, fixed = TRUE))
  expect_match(
    server_source,
    "filter_enrollment_classlist_scope(",
    fixed = TRUE
  )
  expect_match(server_source, '"DESR ", tab_display', fixed = TRUE)
})

test_that("Gen Ed guide uses the shared DFW definition and fixed display threshold", {
  guide <- paste(readLines(file.path(cedar_base_dir, "docs/users/gen-ed.md"),
                           warn = FALSE), collapse = "\n")

  expect_match(guide, 'include definition-summary.html id="dfw"', fixed = TRUE)
  expect_match(guide, "fixed five-attempt display threshold", fixed = TRUE)
  expect_match(guide, "DFW % equals Non-W DFW % plus W %", fixed = TRUE)
  expect_match(guide, "not calculated from only the visible course rows", fixed = TRUE)
  expect_false(grepl("| **Min N**", guide, fixed = TRUE))
  expect_false(grepl("The scope stripe summarizes", guide, fixed = TRUE))
  expect_false(grepl("below-C measures", guide, fixed = TRUE))
})
