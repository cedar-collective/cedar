context("Class-list waitlist preservation")

source("../../R/data-parsers/class-list-waitlists.R")


test_that("preserve_class_list_waitlists keeps old WL rows missing from a refreshed term", {
  old_data <- tibble::tibble(
    `Academic Period` = c("Fall 2025", "Fall 2025", "Spring 2026"),
    `Academic Period Code` = c(202580L, 202580L, 202610L),
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
    `Course Reference Number` = "10003",
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
