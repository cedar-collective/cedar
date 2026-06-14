test_that("get_cancellations includes only C status in cancelled sections", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = c(202010L, 202060L, 202080L, 202110L),
    level = NULL
  )))

  expect_equal(nrow(result$cancelled_sections), 8)
  expect_true(all(result$cancelled_sections$status == "C"))
  expect_false(any(result$cancelled_sections$status %in% c("R", "S")))
})

test_that("get_cancellations reports R and S status counts separately", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = c(202010L, 202060L, 202080L, 202110L),
    level = NULL
  )))

  expect_equal(result$status_note$n_sections[result$status_note$status == "R"], 1)
  expect_equal(result$status_note$n_sections[result$status_note$status == "S"], 1)
})

test_that("get_cancellations reports zero R and S counts when none match", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = 202060L,
    dept = "ANTH",
    level = NULL
  )))

  expect_equal(result$status_note$n_sections[result$status_note$status == "R"], 0)
  expect_equal(result$status_note$n_sections[result$status_note$status == "S"], 0)
})

test_that("get_cancellations parses cancellation timing relative to start_date", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = 202010L,
    dept = "HIST",
    level = NULL
  )))

  row <- result$cancelled_sections %>%
    dplyr::filter(section_id == "S10C01") %>%
    dplyr::slice(1)

  expect_equal(row$canceled_on, as.Date("2020-01-06"))
  expect_equal(row$start_date, as.Date("2020-01-13"))
  expect_equal(row$timing_reference, "start_date")
  expect_equal(row$timing_reference_date, as.Date("2020-01-13"))
  expect_equal(row$days_before_start, 7L)
  expect_equal(row$days_before_census, 22L)
})

test_that("get_cancellations ranks commonly cancelled courses", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = c(202010L, 202060L, 202080L, 202110L),
    level = NULL
  )))

  anth <- result$common_courses %>%
    dplyr::filter(subject_course == "ANTH 3500") %>%
    dplyr::slice(1)
  expect_equal(anth$n_cancelled_sections, 2L)
  expect_equal(anth$n_terms_cancelled, 2L)
})

test_that("get_cancellations returns department-term and timing tables", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = c(202010L, 202060L),
    level = NULL
  )))

  expect_named(
    result$by_department_term,
    c("term", "term_label", "department", "n_cancelled")
  )
  expect_equal(sum(result$by_department_term$n_cancelled), 4L)

  expect_named(
    result$timing,
    c("department", "days_before_start", "n_cancelled")
  )
  expect_equal(sum(result$timing$n_cancelled), 2L)
})

test_that("get_cancellations trends ignore specific term-code filters", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = 202010L,
    level = NULL
  )))

  expect_named(
    result$trends,
    c("term", "term_label", "department", "n_cancelled")
  )
  expect_equal(sum(result$trends$n_cancelled), 8L)
  expect_equal(sort(unique(result$trends$term)), c(202010L, 202060L, 202080L, 202110L))
})

test_that("get_cancellations trends retain seasonal term filters", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = "spring",
    level = NULL
  )))

  expect_equal(sum(result$trends$n_cancelled), 4L)
  expect_equal(sort(unique(result$trends$term)), c(202010L, 202110L))
})

test_that("get_cancellations reports timing rows omitted before the 100-day window", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = 202080L,
    dept = "ANTH",
    level = NULL
  )))

  expect_equal(result$timing_omitted, 1L)
  expect_equal(nrow(result$timing), 0)
})

test_that("get_cancellations returns timing audit counts", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = c(202010L, 202060L, 202080L, 202110L),
    level = NULL
  )))

  expect_named(
    result$timing_summary,
    c(
      "total_cancelled", "parsed_cancel_date", "missing_cancel_date",
      "missing_start_date", "missing_census_date", "missing_timing_reference",
      "timing_window_0_100", "earlier_than_100_days",
      "after_start", "parse_rate"
    )
  )
  expect_equal(result$timing_summary$total_cancelled, 8L)
  expect_equal(result$timing_summary$parsed_cancel_date, 8L)
  expect_equal(result$timing_summary$missing_cancel_date, 0L)
  expect_equal(result$timing_summary$timing_window_0_100, 3L)
  expect_equal(result$timing_summary$earlier_than_100_days, 1L)
  expect_equal(result$timing_summary$after_start, 4L)
})

test_that("get_cancellations parses cancelled spelling and colon date comments", {
  sections <- test_sections %>%
    dplyr::mutate(
      comments = dplyr::if_else(
        section_id == "S10C01",
        "Cancelled: 01/07/2020",
        comments
      )
    )

  result <- get_cancellations(sections, create_test_opt(list(
    term = 202010L,
    dept = "HIST",
    level = NULL
  )))

  row <- result$cancelled_sections %>%
    dplyr::filter(section_id == "S10C01") %>%
    dplyr::slice(1)

  expect_equal(row$canceled_on, as.Date("2020-01-07"))
  expect_equal(row$days_before_start, 6L)
  expect_equal(row$days_before_census, 21L)
})

test_that("get_cancellations handles empty cancelled results", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = 202010L,
    dept = "NURS",
    level = NULL
  )))

  expect_equal(nrow(result$cancelled_sections), 0)
  expect_equal(nrow(result$by_department_term), 0)
  expect_equal(nrow(result$timing), 0)
  expect_equal(nrow(result$common_courses), 0)
})

test_that("get_cancellations keeps expected common-course column types", {
  result <- get_cancellations(test_sections, create_test_opt(list(
    term = c(202010L, 202060L, 202080L, 202110L),
    level = NULL
  )))

  expect_type(result$common_courses$n_cancelled_sections, "integer")
  expect_type(result$common_courses$n_terms_cancelled, "integer")
  expect_type(result$common_courses$median_days_before_start, "double")
})
