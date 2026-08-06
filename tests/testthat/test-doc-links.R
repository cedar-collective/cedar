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
