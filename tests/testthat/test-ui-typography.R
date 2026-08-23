context("Shared UI typography")

test_that("prose measures are centralized by reading purpose", {
  css <- paste(readLines("../../www/cedar-custom.css", warn = FALSE),
               collapse = "\n")

  expect_match(css, "--prose-measure-long:     80ch", fixed = TRUE)
  expect_match(css, "--prose-measure-standard: 90ch", fixed = TRUE)
  expect_match(css, "--prose-measure-brief:   105ch", fixed = TRUE)

  expect_match(
    css,
    "\\.cedar-lead[\\s\\S]{0,220}max-width: var\\(--prose-measure-brief\\)",
    perl = TRUE
  )
  expect_match(
    css,
    "\\.cedar-body[\\s\\S]{0,220}max-width: var\\(--prose-measure-standard\\)",
    perl = TRUE
  )
  expect_match(
    css,
    "\\.cedar-subtab-description[\\s\\S]{0,220}max-width: var\\(--prose-measure-brief\\)",
    perl = TRUE
  )
})

test_that("long-form methodology constrains prose rather than its tables", {
  css <- paste(readLines("../../www/cedar-custom.css", warn = FALSE),
               collapse = "\n")
  pathways <- paste(readLines("../../R/modules/pathways.R", warn = FALSE),
                    collapse = "\n")

  expect_match(pathways, 'div\\(class = "cedar-methodology"', perl = TRUE)
  expect_false(grepl('style = "max-width: 820px', pathways, fixed = TRUE))
  expect_match(
    css,
    "\\.cedar-methodology > p,[\\s\\S]{0,180}var\\(--prose-measure-long\\)",
    perl = TRUE
  )
  expect_false(grepl(".cedar-methodology > table", css, fixed = TRUE))
})
