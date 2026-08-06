context("Documentation links")

source("../../R/modules/ui-helpers.R")


test_that("cedar_docs_link builds standard external docs links", {
  link <- cedar_docs_link("users/regstats#saturation")
  html <- as.character(link)

  expect_match(html, 'href="https://cedarplatform.org/users/regstats#saturation"', fixed = TRUE)
  expect_match(html, 'target="_blank"', fixed = TRUE)
  expect_match(html, 'rel="noopener"', fixed = TRUE)
  expect_match(html, "Full methodology", fixed = TRUE)
})


test_that("app UI code uses the shared docs link helper", {
  files <- c(
    "../../ui.R",
    setdiff(
      list.files("../../R/modules", pattern = "\\.R$", full.names = TRUE),
      "../../R/modules/ui-helpers.R"
    ),
    list.files("../../R/features", pattern = "\\.R$", full.names = TRUE)
  )
  contents <- vapply(files, function(path) {
    paste(readLines(path, warn = FALSE), collapse = "\n")
  }, character(1))

  hardcoded <- grep("https://cedarplatform.org", contents, fixed = TRUE, value = TRUE)

  expect_length(hardcoded, 0)
})


test_that("Pathways subtabs link to the user guide", {
  pathways <- paste(readLines("../../R/modules/pathways.R", warn = FALSE), collapse = "\n")
  anchors <- c(
    "build-a-population",
    "roadblocks",
    "course-timing",
    "course-pairs",
    "course-to-major",
    "major-changes",
    "methodology"
  )

  for (anchor in anchors) {
    expect_match(pathways, paste0('pathways_guide_link\\("', anchor, '"\\)'))
  }
})


test_that("Pathways major group presets use population-oriented names", {
  files <- c("../../R/lists/population-presets.R", "../../R/modules/pathways.R")
  contents <- paste(vapply(files, function(path) {
    paste(readLines(path, warn = FALSE), collapse = "\n")
  }, character(1)), collapse = "\n")

  expect_match(contents, "PATHWAYS_MAJOR_GROUP_PRESETS", fixed = TRUE)
  expect_match(contents, "DEFAULT_MAJOR_GROUP_PROGRAMS", fixed = TRUE)
  expect_false(grepl("COHORT_PRESETS", contents, fixed = TRUE))
  expect_false(grepl("DEFAULT_HEALTH_PROGRAMS", contents, fixed = TRUE))
})
