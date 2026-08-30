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
})
