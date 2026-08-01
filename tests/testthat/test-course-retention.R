context("Course Retention")

test_that("retention benchmark differences are expressed in percentage points", {
  course <- tibble::tibble(
    term = c(202310L, 202410L),
    term_label = c("Spr 2023", "Spr 2024"),
    n = c(20L, 25L),
    ret_1 = c(0.80, 0.70),
    ret_2 = c(0.75, NA_real_)
  )
  dept <- tibble::tibble(
    term = c(202310L, 202410L),
    term_label = c("Spr 2023", "Spr 2024"),
    n = c(200L, 220L),
    ret_1 = c(0.72, 0.75),
    ret_2 = c(0.70, NA_real_)
  )
  college <- tibble::tibble(
    term = c(202310L, 202410L),
    term_label = c("Spr 2023", "Spr 2024"),
    n = c(900L, 920L),
    ret_1 = c(0.76, 0.68),
    ret_2 = c(0.71, NA_real_)
  )

  diffs <- compare_retention_to_benchmarks(course, dept, college)

  expect_setequal(diffs$benchmark, c("Department", "College"))
  expect_equal(
    diffs$diff_pct[diffs$term == 202310L & diffs$benchmark == "Department" & diffs$horizon_n == 1L],
    8
  )
  expect_equal(
    diffs$diff_pct[diffs$term == 202410L & diffs$benchmark == "College" & diffs$horizon_n == 1L],
    2
  )
  expect_false(any(is.na(diffs$diff_pct)))
})

test_that("instructor retention summaries return top and bottom rows", {
  retention <- tibble::tibble(
    term = c(202110L, 202210L, 202310L),
    term_label = c("Spr 2021", "Spr 2022", "Spr 2023"),
    instructor_id = c("A", "B", "C"),
    n = c(25L, 20L, 30L),
    ret_1 = c(0.90, 0.60, 0.75),
    ret_2 = c(0.80, 0.50, NA_real_)
  )

  ranked <- summarize_instructor_retention_rows(retention, top_n = 2L)

  expect_equal(ranked$top$instructor_id, c("A", "C"))
  expect_equal(ranked$bottom$instructor_id, c("B", "C"))
  expect_equal(round(ranked$top$avg_retention[[1]], 2), 0.85)
})

test_that("instructor retention trend displays instructor names when available", {
  students <- tibble::tibble(
    student_id = c("S1", "S2", "S3", "S1", "S2"),
    term = c(202110L, 202110L, 202110L, 202180L, 202180L),
    subject_course = c("HIST 101", "HIST 101", "HIST 101", "OTHER 100", "OTHER 100"),
    registration_status_code = STATUS_REGISTERED[[1]],
    campus = "ABQ",
    instructor_id = c("enc-a", "enc-a", "enc-b", NA_character_, NA_character_),
    instructor_name = c("Adams, Erin", "Adams, Erin", "Baker, Lee", NA_character_, NA_character_)
  )

  result <- get_retention_trend(
    students,
    opt = list(course = "HIST 101", by_instructor = TRUE, n_terms = 1L, min_n = 1L)
  )

  expect_true("instructor_name" %in% names(result))
  expect_setequal(result$instructor_name, c("Adams, Erin", "Baker, Lee"))
  expect_setequal(result$instructor_id, c("enc-a", "enc-b"))
  expect_equal(result$ret_1[result$instructor_name == "Adams, Erin"], 1)
  expect_equal(result$ret_1[result$instructor_name == "Baker, Lee"], 0)
})


# ── Campus policy ────────────────────────────────────────────────────────────
#
# Retention splits the cohort by campus but measures the outcome UNM-wide. Both
# halves matter: grouping by campus stops a branch cohort being reported as a
# main-campus rate, and keeping the outcome UNM-wide stops a campus transfer
# being counted as attrition.

test_that("retention is grouped by campus, not blended across campuses", {
  r <- suppressMessages(get_retention_trend(
    test_students_mcret,
    opt = list(course = "MCRT 101", n_terms = 1L, min_n = 1L)
  ))

  expect_true("campus" %in% names(r))
  expect_setequal(r$campus, c("ABQ", "GA"))
  expect_equal(r$n[r$campus == "ABQ"], 2L)
  expect_equal(r$n[r$campus == "GA"], 2L)

  # The whole point: these must not average into one number.
  expect_equal(r$ret_1[r$campus == "ABQ"], 1.0)
  expect_equal(r$ret_1[r$campus == "GA"], 0.5)
})

test_that("a student who moves campuses is retained, not counted as attrition", {
  # S3 took the course at Gallup and came back at Albuquerque. Retention asks
  # whether they stayed at UNM, so this is a success. Scoping the outcome to the
  # cohort's campus would score it as a stop-out and understate every branch.
  r <- suppressMessages(get_retention_trend(
    test_students_mcret,
    opt = list(course = "MCRT 101", n_terms = 1L, min_n = 1L)
  ))
  expect_equal(r$ret_1[r$campus == "GA"], 0.5)   # S3 retained, S4 not
})

test_that("opt$campus restricts the cohort without changing the outcome rule", {
  r <- suppressMessages(get_retention_trend(
    test_students_mcret,
    opt = list(course = "MCRT 101", n_terms = 1L, min_n = 1L, campus = "GA")
  ))
  expect_equal(nrow(r), 1L)
  expect_equal(r$campus, "GA")
  # Still 0.5 — S3's return at ABQ still counts even though the cohort is GA.
  expect_equal(r$ret_1, 0.5)
})

test_that("a students frame with no campus column fails loudly", {
  # Silently dropping campus from the grouping is the exact failure this policy
  # exists to prevent, so it must not degrade quietly to a blended rate.
  no_campus <- dplyr::select(test_students_mcret, -campus)
  expect_error(
    suppressMessages(get_retention_trend(
      no_campus, opt = list(course = "MCRT 101", n_terms = 1L, min_n = 1L))),
    "campus"
  )
})

test_that("benchmark comparison joins on campus and does not fan out", {
  # course_result and the benchmark are both per campus. Joining on term alone
  # would match each course row to every campus's benchmark for that term.
  course <- tibble::tibble(
    campus = c("ABQ", "GA"), term = 202110L, term_label = "Fall 2021",
    n = c(10L, 10L), ret_1 = c(0.9, 0.5)
  )
  bench <- tibble::tibble(
    campus = c("ABQ", "GA"), term = 202110L, term_label = "Fall 2021",
    n = c(100L, 100L), ret_1 = c(0.8, 0.4)
  )
  d <- compare_retention_to_benchmarks(course, bench)

  expect_equal(nrow(d), 2)                       # not 4
  expect_setequal(d$campus, c("ABQ", "GA"))
  expect_equal(d$diff_pct[d$campus == "ABQ"], 10)
  expect_equal(d$diff_pct[d$campus == "GA"], 10)
})
