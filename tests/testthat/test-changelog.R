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

test_that("every changelog entry is complete, newest first, and every link opens a page", {
  changelog <- load_changelog()
  versions <- vapply(changelog, `[[`, character(1), "version")
  expect_false(any(duplicated(versions)))
  dates <- as.Date(vapply(changelog, `[[`, character(1), "date"))
  expect_false(anyNA(dates))
  expect_false(is.unsorted(rev(dates)))
  for (entry in changelog) {
    expect_true(all(c("version", "date", "title", "type", "items") %in% names(entry)), info = entry$version)
    expect_gt(length(changelog_entry_items_html(entry)), 0)
  }
  # The rule since v2.2.0: every item of the version being written says what
  # it does for a reader (release-runbook.md#the-changelog).
  expect_true(all(vapply(changelog[[1]]$items, function(item) is.list(item) && nzchar(item$text %||% ""), logical(1))))

  highlights <- get_recent_highlights(max = Inf)
  improvements <- get_recent_improvements(max = Inf)
  # A highlight with no tab links to the Changelog.
  expect_true(all(vapply(highlights, function(x) all(c("title", "text", "icon") %in% names(x)), logical(1))))
  expect_true(all(vapply(highlights, function(x) x$icon %in% fontawesome::fa_metadata()$icon_names, logical(1))))
  tabs <- unlist(c(lapply(highlights, `[[`, "tab"), lapply(improvements, `[[`, "tab")))
  expect_true(all(vapply(tabs, function(tab) !is.null(cedar_tab_from_slug(tab)), logical(1))))

  # The homepage strip draws from the newest two releases.
  expect_gte(length(get_recent_highlights(max = 12, release_count = 2)), 4L)
})

test_that("the Changelog page shows the latest release once, then the earlier ones", {
  changelog <- load_changelog()
  latest <- get_recent_changelog(max_entries = 1)
  earlier <- get_earlier_changelog(after = 1)
  expect_identical(c(latest, earlier), changelog)
  expect_false(latest[[1]]$version %in% vapply(earlier, `[[`, character(1), "version"))
})

test_that("a release lists its items by what each does for a reader, escaped", {
  entry <- list(version = "v0.0.1", date = "2026-01-01", title = "A & B", type = "minor", items = list(
    list(kind = "hood", text = "Tests run faster."),
    list(kind = "new", text = "A page for <id>."),
    list(kind = "clearer", text = "Each count says who it counts.")))
  testthat::local_edition(3)
  expect_snapshot(cat(format_changelog_html(list(entry)), sep = "\n"))
  entry$items[[1]]$kind <- "optimization"
  expect_error(changelog_entry_items_html(entry), "kind must be one of")
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
