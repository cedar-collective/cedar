context("Changelog Helpers")

test_that("recent changelog item selection preserves order by default", {
  items <- lapply(letters[1:6], function(x) list(title = x))

  selected <- select_recent_changelog_items(items, max = 3)

  expect_equal(vapply(selected, `[[`, character(1), "title"), letters[1:3])
})

test_that("recent changelog item selection samples only from requested pool", {
  items <- lapply(letters[1:6], function(x) list(title = x))

  set.seed(42)
  selected <- select_recent_changelog_items(items, max = 3, random = TRUE, pool = 4)
  selected_titles <- vapply(selected, `[[`, character(1), "title")

  expect_length(selected_titles, 3)
  expect_true(all(selected_titles %in% letters[1:4]))
  expect_false(any(selected_titles %in% letters[5:6]))
})

test_that("homepage changelog highlights and improvements load from config", {
  highlights <- get_recent_highlights(
    max = 4, random = TRUE, pool = 12, release_count = 1
  )
  improvements <- get_recent_improvements(
    max = 6, random = TRUE, pool = 18, release_count = 1
  )

  expect_length(highlights, 4)
  expect_true(all(vapply(highlights, function(x) {
    all(c("title", "text", "date", "tab") %in% names(x))
  }, logical(1))))

  expect_length(improvements, 6)
  expect_true(all(vapply(improvements, function(x) {
    all(c("title", "date") %in% names(x))
  }, logical(1))))
  expect_true(all(vapply(highlights, `[[`, character(1), "version") == get_cedar_version()))
  expect_true(all(vapply(improvements, `[[`, character(1), "version") == get_cedar_version()))
})

test_that("UTF-8 changelog and spotlights load in the C locale", {
  old_locale <- Sys.getlocale("LC_CTYPE")
  on.exit(suppressWarnings(Sys.setlocale("LC_CTYPE", old_locale)), add = TRUE)
  expect_true(nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))))

  changelog <- load_changelog()
  spotlights <- load_feature_spotlights()

  expect_gte(length(changelog), 40L)
  expect_match(changelog[[1]]$title, intToUtf8(0x2014), fixed = TRUE)
  expect_gt(length(spotlights), 0L)
  expect_true(any(grepl("[^\\x01-\\x7F]", unlist(changelog), perl = TRUE)))
})
