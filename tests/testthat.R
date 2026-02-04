# testthat entry point
# This file is run by R CMD check and devtools::test()

# Test runner for CEDAR project
# Run all tests in tests/testthat/

library(testthat)

# Run all tests in the testthat directory
test_dir("tests/testthat", reporter = "progress")
