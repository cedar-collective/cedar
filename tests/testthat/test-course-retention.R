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
