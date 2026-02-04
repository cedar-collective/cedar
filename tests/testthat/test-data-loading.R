# Tests for data loading functions
# Tests functions in R/branches/load-funcs.R and R/branches/data.R

context("Data Loading")

test_that("load_global_data loads all required data objects", {
  # opt <- create_test_opt()
  
  # This would require access to actual data files
  # load_global_data(opt)
  
  # expect_true(exists("courses"))
  # expect_true(exists("students"))
  # expect_true(exists("academic_studies"))
  # expect_true(exists("degrees"))
  
  skip("Requires actual data files")
})

test_that("data files have expected structure", {
  # Test that loaded .Rds files have required columns
  skip("Requires actual data files")
})

test_that("data files are not empty", {
  # Test that loaded data has rows
  skip("Requires actual data files")
})

test_that("data objects match report_specs", {
  # Test that each data object corresponds to a parser spec
  skip("Requires actual data files")
})
