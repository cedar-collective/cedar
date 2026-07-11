test_that("SFR department matching finds valid data for departments", {
  test_opt <- list()

  # Get headcount data to simulate what happens in get_sfr()
  result <- get_headcount(test_programs, test_opt,
                         group_by = c("term", "dept_code", "student_level", "program_type", "program_name"))
  headcount_all <- result$data

  expect_gt(nrow(headcount_all), 0)

  # Check that dept_code column has values
  unique_depts <- unique(headcount_all$dept_code)
  expect_gt(length(unique_depts), 0)

  # Dept codes are 4-char strings (HIST, MATH, ANTH) — mean > 3
  dept_lengths <- nchar(unique_depts)
  expect_true(mean(dept_lengths) > 3)

  # Verify History program exists and is accessible
  hist_filter <- headcount_all %>%
    filter(program_name == "History")

  expect_gt(nrow(hist_filter), 0)

  # Check the dept_code values for History program
  hist_dept_codes <- unique(hist_filter$dept_code)

  # Verify HIST dept code is present
  target_code <- "HIST"
  matching_dept <- NA_character_

  # Try exact match first
  exact_matches <- hist_filter %>%
    filter(dept_code == target_code) %>%
    distinct(dept_code) %>%
    pull(dept_code)

  if (length(exact_matches) > 0) {
    matching_dept <- exact_matches[1]
  } else {
    # Try partial match
    partial_matches <- hist_dept_codes[grepl(target_code, hist_dept_codes, ignore.case = TRUE)]
    if (length(partial_matches) > 0) {
      matching_dept <- partial_matches[1]
    }
  }

  expect_false(is.na(matching_dept))

  # Now verify that filtering with the matched dept_code returns data
  filtered_data <- hist_filter %>%
    filter(dept_code == matching_dept)

  expect_gt(nrow(filtered_data), 0)
})


test_that("SFR data is non-empty for departments with students and faculty", {
  test_opt <- list()

  # Simulate what get_sfr() does
  hc_result <- get_headcount(test_programs, test_opt,
                            group_by = c("term", "dept_code", "student_level", "program_type", "program_name"))
  studfac_ratios <- hc_result$data

  expect_equal(nrow(studfac_ratios), 37L)

  # Find matching department
  unique_depts <- unique(studfac_ratios$dept_code)
  hist_dept <- unique_depts[grepl("HIST", unique_depts, ignore.case = TRUE)][1]

  expect_equal(hist_dept, "HIST")

  # Filter for undergrad History
  ug_hist <- studfac_ratios %>%
    filter(student_level == "Undergraduate") %>%
    filter(dept_code == hist_dept)

  expect_equal(nrow(ug_hist), 4L)

  # Filter for grad History
  grad_hist <- studfac_ratios %>%
    filter(student_level == "Graduate/GASM") %>%
    filter(dept_code == hist_dept)

  # Fixture has no graduate History programs; the filter must still run cleanly
  expect_equal(nrow(grad_hist), 0L)
})
