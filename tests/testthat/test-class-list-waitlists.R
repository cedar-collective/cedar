context("Class-list waitlist preservation")

source("../../R/data-parsers/class-list-waitlists.R")


test_that("preserve_class_list_waitlists keeps old WL rows missing from a refreshed term", {
  old_data <- tibble::tibble(
    `Academic Period` = c("Fall 2025", "Fall 2025", "Spring 2026"),
    `Academic Period Code` = c("202580", "202580", "202610"),
    `Student ID` = c("wl-old", "re-old", "wl-other-term"),
    `Course Reference Number` = c("10001", "10002", "20001"),
    `Registration Status Code` = c("WL", "RE", "WL"),
    `Final Grade` = c(NA_character_, "A", NA_character_),
    as_of_date = as.Date(c("2025-08-01", "2025-12-20", "2026-01-01"))
  )
  new_data <- tibble::tibble(
    `Academic Period` = "Fall 2025",
    `Academic Period Code` = 202580L,
    `Student ID` = "re-new",
    `Course Reference Number` = 10003L,
    `Registration Status Code` = "RE",
    `Final Grade` = "B",
    as_of_date = as.Date("2025-12-20")
  )

  result <- preserve_class_list_waitlists(old_data, new_data)

  expect_equal(attr(result, "n_preserved_wl"), 1L)
  expect_true("wl-old" %in% result$`Student ID`)
  expect_false("re-old" %in% result$`Student ID`)
  expect_false("wl-other-term" %in% result$`Student ID`)
})


test_that("preserve_class_list_waitlists does not duplicate WL rows still present in new data", {
  old_data <- tibble::tibble(
    `Academic Period` = "Fall 2025",
    `Academic Period Code` = 202580L,
    `Student ID` = "wl-still-present",
    `Course Reference Number` = "10001",
    `Registration Status Code` = "WL",
    as_of_date = as.Date("2025-08-01")
  )
  new_data <- tibble::tibble(
    `Academic Period` = "Fall 2025",
    `Academic Period Code` = 202580L,
    `Student ID` = "wl-still-present",
    `Course Reference Number` = "10001",
    `Registration Status Code` = "WL",
    as_of_date = as.Date("2025-12-20")
  )

  result <- preserve_class_list_waitlists(old_data, new_data)

  expect_equal(attr(result, "n_preserved_wl"), 0L)
  expect_equal(sum(result$`Student ID` == "wl-still-present"), 1L)
  expect_equal(result$as_of_date, as.Date("2025-12-20"))
})


test_that("preserve_class_list_waitlists normalizes mixed-type join keys", {
  old_data <- tibble::tibble(
    `Academic Period` = "Fall 2026",
    `Academic Period Code` = "202680",
    `Student ID` = "wl-still-present",
    `Course Reference Number` = "12345",
    `Sub-Academic Period Code` = "1",
    `Registration Status Code` = "WL",
    as_of_date = as.Date("2026-07-29")
  )
  new_data <- tibble::tibble(
    `Academic Period` = "Fall 2026",
    `Academic Period Code` = 202680L,
    `Student ID` = "wl-still-present",
    `Course Reference Number` = 12345L,
    `Sub-Academic Period Code` = 1L,
    `Registration Status Code` = "WL",
    as_of_date = as.Date("2026-08-05")
  )

  expect_no_error(result <- preserve_class_list_waitlists(old_data, new_data))

  expect_equal(attr(result, "n_preserved_wl"), 0L)
  expect_equal(sum(result$`Student ID` == "wl-still-present"), 1L)
  expect_equal(result$as_of_date, as.Date("2026-08-05"))
})


test_that("class-list refresh preserves WL rows across fread type drift", {
  old_data <- tibble::tibble(
    `Academic Period` = c("Fall 2026", "Fall 2026", "Fall 2026"),
    `Academic Period Code` = c("202680", "202680", "202680"),
    `Student ID` = c("wl-missing-from-new", "wl-still-present", "re-old"),
    `Course Reference Number` = c("12345", "67890", "24680"),
    `Sub-Academic Period Code` = c("1", "1", "1"),
    `Registration Status Code` = c("WL", "WL", "RE"),
    as_of_date = as.Date(c("2026-07-29", "2026-07-29", "2026-07-29"))
  )
  new_data <- tibble::tibble(
    `Academic Period` = c("Fall 2026", "Fall 2026"),
    `Academic Period Code` = c(202680L, 202680L),
    `Student ID` = c("wl-still-present", "re-new"),
    `Course Reference Number` = c(67890L, 13579L),
    `Sub-Academic Period Code` = c(1L, 1L),
    `Registration Status Code` = c("WL", "RE"),
    as_of_date = as.Date(c("2026-08-05", "2026-08-05"))
  )

  expect_no_error(result <- preserve_class_list_waitlists(old_data, new_data))

  expect_equal(attr(result, "n_preserved_wl"), 1L)
  expect_true("wl-missing-from-new" %in% result$`Student ID`)
  expect_equal(sum(result$`Student ID` == "wl-still-present"), 1L)
  expect_false("re-old" %in% result$`Student ID`)
  expect_type(result$`Academic Period Code`, "character")
  expect_type(result$`Course Reference Number`, "character")
})
