context("Documentation links")

source("../../R/modules/ui-helpers.R")


test_that("cedar_docs_link builds standard external docs links", {
  link <- cedar_docs_link("users/regstats#saturation")
  html <- as.character(link)

  expect_match(html, 'href="https://cedarplatform.org/users/regstats#saturation"', fixed = TRUE)
  expect_match(html, 'target="_blank"', fixed = TRUE)
  expect_match(html, 'rel="noopener"', fixed = TRUE)
})
