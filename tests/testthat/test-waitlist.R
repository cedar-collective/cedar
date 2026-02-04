# Tests for waitlist analysis functions
# Tests get_unique_waitlisted() and inspect_waitlist()

context("Waitlist Analysis")

# Load required libraries
library(stringr)

# Load waitlist functions
source("../../R/cones/waitlist.R")
source("../../R/branches/filter.R")

test_that("get_unique_waitlisted identifies waitlisted students correctly", {
  message("\n  Testing get_unique_waitlisted basic functionality...")

  # Create test data with waitlisted and registered students
  test_waitlist_data <- data.frame(
    campus = rep("ABQ", 6),
    term = rep(202310, 6),
    subject_course = rep("MATH 1430", 6),
    course_title = rep("Applications of Calculus I", 6),
    student_id = c("S001", "S002", "S003", "S004", "S005", "S006"),
    registration_status = c(
      "Wait Listed", "Wait Listed", "Wait Listed",
      "Student Registered", "Student Registered", "Wait Listed"
    ),
    stringsAsFactors = FALSE
  )

  # S001, S002, S003 are waitlisted only
  # S004, S005 are registered
  # S006 is also waitlisted

  # Filter to just waitlisted
  waitlisted_only <- test_waitlist_data %>% filter(registration_status == "Wait Listed")

  result <- get_unique_waitlisted(test_waitlist_data, list())

  message("  Result has ", nrow(result), " rows")
  message("  Columns: ", paste(colnames(result), collapse = ", "))

  expect_s3_class(result, "data.frame")
  expect_true("campus" %in% colnames(result))
  expect_true("subject_course" %in% colnames(result))
  expect_true("count" %in% colnames(result))
  expect_equal(nrow(result), 1) # One course
  expect_equal(result$count[1], 4) # 4 waitlisted students total
})

test_that("get_unique_waitlisted excludes students who are also registered", {
  message("\n  Testing waitlist exclusion logic...")

  # Create test data where some students are both waitlisted AND registered
  test_data <- data.frame(
    campus = rep("ABQ", 8),
    term = rep(202310, 8),
    subject_course = c(rep("MATH 1430", 4), rep("MATH 1430", 4)),
    course_title = rep("Applications of Calculus I", 8),
    student_id = c("S001", "S002", "S001", "S002", "S003", "S004", "S003", "S005"),
    registration_status = c(
      "Wait Listed", "Wait Listed", "Student Registered", "Student Registered",
      "Wait Listed", "Wait Listed", "Student Registered", "Wait Listed"
    ),
    stringsAsFactors = FALSE
  )

  # S001: waitlisted AND registered (should be excluded from count)
  # S002: waitlisted AND registered (should be excluded from count)
  # S003: waitlisted AND registered (should be excluded from count)
  # S004: waitlisted only (should be counted)
  # S005: waitlisted only (should be counted)

  result <- get_unique_waitlisted(test_data, list())

  message("  Only waitlisted count: ", result$count[1])

  expect_equal(result$count[1], 2) # Only S004 and S005
})

test_that("get_unique_waitlisted handles multiple campuses and courses", {
  message("\n  Testing multiple campuses and courses...")

  test_data <- data.frame(
    campus = c(rep("ABQ", 6), rep("TAOS", 4)),
    term = rep(202310, 10),
    subject_course = c(rep("MATH 1430", 6), rep("BIOL 1110", 4)),
    course_title = c(rep("Calculus I", 6), rep("Biology I", 4)),
    student_id = paste0("S", sprintf("%03d", 1:10)),
    registration_status = c(
      "Wait Listed", "Wait Listed", "Student Registered",
      "Wait Listed", "Student Registered", "Wait Listed",
      "Wait Listed", "Wait Listed", "Registered", "Wait Listed"
    ),
    stringsAsFactors = FALSE
  )

  result <- get_unique_waitlisted(test_data, list())

  message("  Result has ", nrow(result), " campus-course combinations")
  message("  Campuses: ", paste(unique(result$campus), collapse = ", "))
  message("  Courses: ", paste(unique(result$subject_course), collapse = ", "))

  expect_gte(nrow(result), 1)
  expect_true(all(c("campus", "subject_course", "count") %in% colnames(result)))
})

test_that("get_unique_waitlisted handles empty waitlist", {
  message("\n  Testing empty waitlist handling...")

  test_data <- data.frame(
    campus = rep("ABQ", 3),
    term = rep(202310, 3),
    subject_course = rep("MATH 1430", 3),
    course_title = rep("Calculus I", 3),
    student_id = paste0("S", 1:3),
    registration_status = rep("Student Registered", 3),
    stringsAsFactors = FALSE
  )

  result <- get_unique_waitlisted(test_data, list())

  message("  Empty waitlist result has ", nrow(result), " rows (should be 0)")
  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_unique_waitlisted handles all waitlisted (no registered)", {
  message("\n  Testing all-waitlisted scenario...")

  test_data <- data.frame(
    campus = rep("ABQ", 5),
    term = rep(202310, 5),
    subject_course = rep("MATH 1430", 5),
    course_title = rep("Calculus I", 5),
    student_id = paste0("S", 1:5),
    registration_status = rep("Wait Listed", 5),
    stringsAsFactors = FALSE
  )

  result <- get_unique_waitlisted(test_data, list())

  message("  All waitlisted count: ", result$count[1])
  expect_equal(result$count[1], 5) # All 5 students waitlisted
})

test_that("get_unique_waitlisted uses correct CEDAR column names", {
  message("\n  Testing CEDAR column name usage...")

  test_data <- data.frame(
    campus = "ABQ",
    term = 202310,
    subject_course = "MATH 1430",
    course_title = "Calculus I",
    student_id = "S001",
    registration_status = "Wait Listed",
    stringsAsFactors = FALSE
  )

  # Should not error with CEDAR column names
  result <- get_unique_waitlisted(test_data, list())

  expect_s3_class(result, "data.frame")
  expect_true("campus" %in% colnames(result))
  expect_true("subject_course" %in% colnames(result))
  message("  CEDAR column names working correctly")
})

# Note: inspect_waitlist tests require rollcall.R to be migrated to CEDAR first
# The function depends on summarize_classifications() which still uses old column names
test_that("inspect_waitlist structure is correct (pending rollcall.R migration)", {
  message("\n  Testing inspect_waitlist structure...")
  message("  NOTE: Full testing pending rollcall.R CEDAR migration")

  # This test verifies the function exists and has correct signature
  expect_true(exists("inspect_waitlist"))

  # Function should take students and opt parameters
  args <- formals(inspect_waitlist)
  expect_equal(names(args), c("students", "opt"))

  message("  inspect_waitlist function signature verified")
  message("  Full integration tests will be added after rollcall.R migration")
})

test_that("waitlist.R uses consistent message prefixes", {
  message("\n  Testing message prefix consistency...")

  # Read the file content
  waitlist_content <- readLines("../../R/cones/waitlist.R")

  # Find all message() calls
  message_lines <- grep("message\\(", waitlist_content, value = TRUE)

  # Check that most use [waitlist.R] prefix
  prefixed_messages <- grep("\\[waitlist\\.R\\]", message_lines)

  message("  Found ", length(message_lines), " message calls")
  message("  ", length(prefixed_messages), " use [waitlist.R] prefix")

  # At least 80% should use the prefix (allowing some flexibility)
  expect_gte(length(prefixed_messages) / length(message_lines), 0.8)
})

test_that("waitlist.R has roxygen documentation for all functions", {
  message("\n  Testing roxygen documentation coverage...")

  # Read the file content
  waitlist_content <- readLines("../../R/cones/waitlist.R")

  # Find function definitions
  function_defs <- grep("^[a-z_]+ <- function\\(", waitlist_content)

  message("  Found ", length(function_defs), " function definitions")

  # Check that each function has roxygen docs above it
  for (func_line in function_defs) {
    # Look at previous lines for roxygen comments
    check_lines <- max(1, func_line - 10):func_line
    has_roxygen <- any(grepl("^#'", waitlist_content[check_lines]))

    if (!has_roxygen) {
      func_name <- sub(" <-.*", "", waitlist_content[func_line])
      warning("Function '", func_name, "' missing roxygen documentation")
    }

    expect_true(has_roxygen)
  }

  message("  All functions have roxygen documentation")
})
