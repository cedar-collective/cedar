context("Course Retention")

test_that("a later graduation does not retroactively satisfy earlier horizons", {
  cohort <- tibble::tibble(student_id = "S1", anchor_term = 202010L)
  registered <- tibble::tibble(
    student_id = "other",
    term = c(202080L, 202110L)
  )
  graduated <- tibble::tibble(student_id = "S1", grad_term = 202110L)

  result <- .compute_retention(
    cohort,
    registered_lookup = registered,
    n_terms = 2L,
    graduated_lookup = graduated
  )

  expect_false(result$retained_1)
  expect_true(result$retained_2)
})

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

test_that("retention benchmark plot separates campuses and uses campus joins", {
  diff_data <- tidyr::crossing(
    campus = c("ABQ", "GA"),
    term = c(202310L, 202410L),
    benchmark = c("Department", "College")
  ) %>%
    dplyr::mutate(
      term_label = if_else(term == 202310L, "Spring 2023", "Spring 2024"),
      horizon_n = 1L,
      n_course = if_else(campus == "ABQ", 40L, 12L),
      course_retention_pct = if_else(campus == "ABQ", 80, 55),
      n_benchmark = if_else(benchmark == "Department", 200L, 800L),
      benchmark_retention_pct = dplyr::case_when(
        campus == "ABQ" & benchmark == "Department" ~ 70,
        campus == "ABQ" & benchmark == "College" ~ 75,
        campus == "GA" & benchmark == "Department" ~ 25,
        TRUE ~ 45
      ),
      diff_pct = course_retention_pct - benchmark_retention_pct
    )

  plot <- build_retention_benchmark_plot(diff_data)
  built <- plotly::plotly_build(plot)
  traces <- built$x$data
  course_traces <- Filter(function(trace) identical(trace$name, "Course"), traces)

  expect_s3_class(plot, "plotly")
  expect_length(course_traces, 2L)
  expect_setequal(
    vapply(course_traces, function(trace) trace$xaxis, character(1)),
    c("x", "x2")
  )
  expect_true(any(grepl("Campus: ABQ", unlist(course_traces[[1]]$text))))
  expect_true(any(grepl("vs Dept: 10 pts", unlist(course_traces[[1]]$text))))
  expect_true(any(grepl("Campus: GA", unlist(course_traces[[2]]$text))))
  expect_true(any(grepl("vs Dept: 30 pts", unlist(course_traces[[2]]$text))))
  expect_setequal(
    unique(vapply(traces[seq_len(3)], function(trace) trace$line$color, character(1))),
    unname(CEDAR_PALETTE[seq_len(3)])
  )
})

test_that("retention benchmark plot fails closed without campus data", {
  expect_null(build_retention_benchmark_plot(NULL))
  expect_null(build_retention_benchmark_plot(tibble::tibble()))
  expect_null(build_retention_benchmark_plot(tibble::tibble(term = 202310L)))
})

test_that("instructor retention summaries return top and bottom rows", {
  retention <- tibble::tibble(
    campus = "ABQ",
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

test_that("term-type summaries use cohort-weighted observable rates", {
  retention <- tibble::tibble(
    campus = c("ABQ", "ABQ", "ABQ", "GA"),
    term = c(202310L, 202410L, 202380L, 202310L),
    term_label = c("Spring 2023", "Spring 2024", "Fall 2023", "Spring 2023"),
    n = c(10L, 30L, 20L, 8L),
    ret_1 = c(0.50, 0.90, 0.70, 0.25),
    ret_2 = c(0.40, NA_real_, 0.60, 0.50)
  )

  summary <- summarize_retention_by_term_type(retention)
  abq_spring <- summary %>%
    dplyr::filter(campus == "ABQ", term_type == "spring")

  expect_equal(nrow(abq_spring), 1L)
  expect_equal(abq_spring$terms, 2L)
  expect_equal(abq_spring$n, 40L)
  expect_equal(abq_spring$ret_1, 0.80)
  expect_equal(abq_spring$eligible_1, 40L)
  expect_equal(abq_spring$ret_2, 0.40)
  expect_equal(abq_spring$eligible_2, 10L)
  expect_equal(nrow(summary), 3L)
})

test_that("instructor review ranks instructor-by-term-type aggregates", {
  retention <- tibble::tibble(
    campus = "ABQ",
    term = c(202310L, 202410L, 202310L, 202410L),
    term_label = c("Spring 2023", "Spring 2024", "Spring 2023", "Spring 2024"),
    instructor_id = c("A", "A", "B", "B"),
    instructor_name = c("Adams", "Adams", "Baker", "Baker"),
    n = c(10L, 30L, 20L, 20L),
    ret_1 = c(0.50, 0.90, 0.60, 0.60),
    ret_2 = c(0.40, NA_real_, 0.50, 0.50)
  )

  ranked <- summarize_instructor_retention_rows(retention, top_n = 2L)

  expect_equal(nrow(ranked$top), 2L)
  expect_true(all(ranked$top$terms == 2L))
  expect_equal(ranked$top$instructor_id, c("A", "B"))
  expect_equal(ranked$top$ret_1[[1]], 0.80)
  expect_equal(ranked$top$eligible_2[[1]], 10L)
})

test_that("small instructor terms are pooled before the summary threshold", {
  retention <- tibble::tibble(
    campus = "ABQ",
    term = c(202310L, 202410L, 202510L),
    term_label = c("Spring 2023", "Spring 2024", "Spring 2025"),
    instructor_id = "A",
    instructor_name = "Adams",
    n = c(4L, 5L, 6L),
    ret_1 = c(0.50, 0.60, 0.75),
    ret_2 = c(0.25, NA_real_, NA_real_)
  )

  summary <- summarize_retention_by_term_type(
    retention,
    by_instructor = TRUE,
    min_n = 10L
  )

  expect_equal(nrow(summary), 1L)
  expect_equal(summary$terms, 3L)
  expect_equal(summary$n, 15L)
  expect_equal(summary$eligible_1, 15L)
  expect_equal(summary$ret_1, (4 * 0.50 + 5 * 0.60 + 6 * 0.75) / 15)
  expect_true(is.na(summary$ret_2))
  expect_equal(summary$eligible_2, 4L)
})

test_that("instructor name variations do not fragment term counts", {
  retention <- tibble::tibble(
    campus = "ABQ",
    term = c(202310L, 202410L, 202510L),
    term_label = c("Spring 2023", "Spring 2024", "Spring 2025"),
    instructor_id = "A",
    instructor_name = c("Adams, Erin", "Adams, E.", "Adams, Erin "),
    n = c(12L, 14L, 16L),
    ret_1 = c(0.70, 0.75, 0.80)
  )

  summary <- summarize_retention_by_term_type(
    retention,
    by_instructor = TRUE
  )

  expect_equal(nrow(summary), 1L)
  expect_equal(summary$terms, 3L)
  expect_equal(summary$instructor_id, "A")
  expect_equal(summary$instructor_name, "Adams, Erin")
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

test_that("retention keeps partial current registration out of longitudinal cohorts", {
  students <- tibble::tibble(
    student_id = c("S1", "S2", "S3"),
    term = c(202610L, 202660L, 202680L),
    subject_course = c("HIST 101", "OTHER 100", "HIST 101"),
    registration_status_code = STATUS_REGISTERED[[1]],
    campus = "ABQ"
  )
  edges <- list(
    last_enrolled = 202680L,
    last_enrolled_complete = 202660L,
    last_graded = 202610L
  )

  result <- suppressMessages(get_retention_trend(
    students,
    opt = list(course = "HIST 101", n_terms = 1L, min_n = 1L,
               data_edges = edges)
  ))

  expect_equal(result$term, 202610L)
  expect_true(is.na(result$ret_1))
  expect_false(202680L %in% result$term)
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
