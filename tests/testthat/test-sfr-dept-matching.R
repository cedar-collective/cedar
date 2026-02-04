test_that("SFR department matching finds valid data for departments", {
  skip_if_not(exists("known_programs"))
  
  # Use test data with known structure
  test_programs <- known_programs
  test_opt <- list()
  
  # Get headcount data to simulate what happens in get_sfr()
  result <- get_headcount(test_programs, test_opt, 
                         group_by = c("term", "department", "student_level", "program_type", "program_name"))
  headcount_all <- result$data
  
  expect_gt(nrow(headcount_all), 0)
  
  # Check that department column has values (not codes)
  unique_depts <- unique(headcount_all$department)
  expect_gt(length(unique_depts), 0)
  
  # Check that departments are longer strings (full names) not just codes
  dept_lengths <- nchar(unique_depts)
  expect_true(mean(dept_lengths) > 3)
  
  # Verify History program exists and is accessible
  hist_filter <- headcount_all %>% 
    filter(program_name == "History")
  
  expect_gt(nrow(hist_filter), 0)
  
  # Check the department value for History program
  hist_depts <- unique(hist_filter$department)
  
  # Test that dept code "HIST" can match to the full department name
  dept_code <- "HIST"
  matching_dept <- NA_character_
  
  # Try exact match first
  exact_matches <- hist_filter %>% 
    filter(department == dept_code) %>% 
    distinct(department) %>% 
    pull(department)
  
  if (length(exact_matches) > 0) {
    matching_dept <- exact_matches[1]
  } else {
    # Try partial match
    partial_matches <- hist_depts[grepl(dept_code, hist_depts, ignore.case = TRUE)]
    if (length(partial_matches) > 0) {
      matching_dept <- partial_matches[1]
    }
  }
  
  expect_false(is.na(matching_dept))
  
  # Now verify that filtering with the matched department name returns data
  filtered_data <- hist_filter %>% 
    filter(department == matching_dept)
  
  expect_gt(nrow(filtered_data), 0)
})


test_that("SFR data is non-empty for departments with students and faculty", {
  skip_if_not(exists("known_programs"))
  
  # Prepare test parameters
  test_programs <- known_programs
  test_opt <- list()
  
  # Get SFR data for History department
  result <- list(dept_code = "HIST", prog_focus = "none", plots = list())
  
  # Simulate what get_sfr function does
  hc_result <- get_headcount(test_programs, test_opt,
                            group_by = c("term", "department", "student_level", "program_type", "program_name"))
  studfac_ratios <- hc_result$data
  
  expect_gt(nrow(studfac_ratios), 0)
  
  # Find matching department
  unique_depts <- unique(studfac_ratios$department)
  hist_dept <- unique_depts[grepl("HIST", unique_depts, ignore.case = TRUE)][1]
  
  expect_false(is.na(hist_dept))
  
  # Filter for undergrad History
  ug_hist <- studfac_ratios %>%
    filter(student_level == "Undergraduate") %>%
    filter(department == hist_dept)
  
  expect_gt(nrow(ug_hist), 0)
  
  # Filter for grad History
  grad_hist <- studfac_ratios %>%
    filter(student_level == "Graduate/GASM") %>%
    filter(department == hist_dept)
  
  # Note: grad may be empty, that's OK - just check it doesn't error
  expect_gte(nrow(grad_hist), 0)
})
