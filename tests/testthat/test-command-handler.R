# Tests for command-handler.R
# Tests CLI command routing and option handling
#
# These tests verify:
# 1. command_handler routes to correct functions based on opt$func
# 2. Guide messages are shown when requested
# 3. Required parameters are validated
# 4. Output processing works correctly

context("Command Handler")

# =============================================================================
# Setup - Load command_handler if not already loaded
# =============================================================================

# Try to source command-handler.R if function doesn't exist
if (!exists("command_handler", mode = "function")) {
  command_handler_path <- "R/branches/command-handler.R"
  if (file.exists(command_handler_path)) {
    source(command_handler_path)
  }
}

# =============================================================================
# Helper functions
# =============================================================================

# Check if command_handler is available
skip_if_no_command_handler <- function() {
  skip_if_not(exists("command_handler", mode = "function"),
              "command_handler function not available")
}

# Create minimal opt object for testing
create_test_opt <- function(func = NULL, guide = FALSE, ...) {
  opt <- list(
    func = func,
    guide = guide
  )
  extra <- list(...)
  for (name in names(extra)) {
    opt[[name]] <- extra[[name]]
  }
  opt
}

# =============================================================================
# Basic routing tests
# =============================================================================

test_that("command_handler returns message when no func specified", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = NULL)

  result <- command_handler(opt)

  expect_true(is.character(result))
  expect_match(result, "No function", ignore.case = TRUE)
})

test_that("command_handler routes to credit-hours", {
  skip_if_no_command_handler()
  skip_if_not(exists("filter_class_list", mode = "function"),
              "filter_class_list not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")

  opt <- create_test_opt(func = "credit-hours", term = "202510")

  # Should complete without error (guide = FALSE, has required params)
  result <- command_handler(opt)

  expect_match(result, "credit-hours", ignore.case = TRUE)
})

test_that("command_handler shows credit-hours guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "credit-hours", guide = TRUE)

  # Guide mode should stop with "no error"
  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to headcount", {
  skip_if_no_command_handler()
  skip_if_not(exists("get_headcount", mode = "function"),
              "get_headcount not available")
  skip_if_not(exists("data_objects", envir = .GlobalEnv),
              "data_objects not loaded")

  opt <- create_test_opt(func = "headcount", dept = "HIST")

  result <- command_handler(opt)

  expect_match(result, "headcount", ignore.case = TRUE)
})

test_that("command_handler shows headcount guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "headcount", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to dept-report", {
  skip_if_no_command_handler()
  skip_if_not(exists("create_dept_report", mode = "function"),
              "create_dept_report not available")
  skip_if_not(exists("data_objects", envir = .GlobalEnv),
              "data_objects not loaded")

  opt <- create_test_opt(func = "dept-report", dept = "HIST")

  result <- command_handler(opt)

  expect_match(result, "dept-report", ignore.case = TRUE)
})

test_that("command_handler shows dept-report guide when no dept specified", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "dept-report", guide = TRUE, dept = NULL)

  # Should show guide and return early
  result <- command_handler(opt)

  expect_true(is.character(result))
})

test_that("command_handler routes to enrl", {
  skip_if_no_command_handler()
  skip_if_not(exists("get_enrl", mode = "function"),
              "get_enrl not available")
  skip_if_not(exists("courses", envir = .GlobalEnv),
              "courses data not loaded")

  opt <- create_test_opt(func = "enrl", term = "202510")

  # Should complete without error
  result <- command_handler(opt)

  # enrl doesn't return a message, just processes
  expect_true(is.null(result) || is.character(result))
})

test_that("command_handler shows enrl guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "enrl", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to rollcall", {
  skip_if_no_command_handler()
  skip_if_not(exists("rollcall", mode = "function"),
              "rollcall not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")

  opt <- create_test_opt(func = "rollcall", course = "HIST 1105")

  result <- command_handler(opt)

  expect_true(is.null(result) || is.character(result))
})

test_that("command_handler shows rollcall guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "rollcall", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to gradebook", {
  skip_if_no_command_handler()
  skip_if_not(exists("get_grades", mode = "function"),
              "get_grades not available")
  skip_if_not(exists("data_objects", envir = .GlobalEnv),
              "data_objects not loaded")

  opt <- create_test_opt(func = "gradebook", course = "HIST 1105")

  result <- command_handler(opt)

  expect_true(is.null(result) || is.character(result))
})

test_that("command_handler shows gradebook guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "gradebook", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to regstats", {
  skip_if_no_command_handler()
  skip_if_not(exists("get_reg_stats", mode = "function"),
              "get_reg_stats not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")
  skip_if_not(exists("courses", envir = .GlobalEnv),
              "courses data not loaded")

  opt <- create_test_opt(func = "regstats", term = "202510")

  result <- command_handler(opt)

  expect_true(is.null(result) || is.character(result))
})

test_that("command_handler shows regstats guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "regstats", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to waitlist", {
  skip_if_no_command_handler()
  skip_if_not(exists("inspect_waitlist", mode = "function"),
              "inspect_waitlist not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")

  opt <- create_test_opt(func = "waitlist", course = "ENGL 1110", term = "202510")

  result <- command_handler(opt)

  expect_true(is.null(result) || is.character(result))
})

test_that("command_handler shows waitlist guide when missing params", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "waitlist", guide = TRUE, course = NULL, term = NULL)

  expect_error(command_handler(opt), "no error")
})

# =============================================================================
# Course-report tests
# =============================================================================

test_that("command_handler shows course-report guide when no course specified", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "course-report", guide = TRUE, course = NULL)

  result <- command_handler(opt)

  expect_true(is.character(result))
  expect_match(result, "missing params", ignore.case = TRUE)
})

test_that("command_handler routes to course-report with valid course", {
  skip_if_no_command_handler()
  skip_if_not(exists("create_course_report", mode = "function"),
              "create_course_report not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")
  skip_if_not(exists("courses", envir = .GlobalEnv),
              "courses data not loaded")

  opt <- create_test_opt(func = "course-report", course = "HIST 1105", term = "202510")

  result <- command_handler(opt)

  expect_match(result, "course-report", ignore.case = TRUE)
})

# =============================================================================
# Forecast tests
# =============================================================================

test_that("command_handler shows forecast guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "forecast", guide = TRUE)

  result <- command_handler(opt)

  expect_true(is.character(result))
})

test_that("command_handler validates forecast params", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "forecast",
                         forecast_conduit_term = "202480",
                         term = NULL)  # Missing required term when conduit is specified

  expect_error(command_handler(opt), "target term")
})

# =============================================================================
# Data-status tests
# =============================================================================

test_that("command_handler routes to data-status", {
  skip_if_no_command_handler()
  skip_if_not(exists("get_data_status", mode = "function"),
              "get_data_status not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")

  opt <- create_test_opt(func = "data-status")

  result <- command_handler(opt)

  expect_match(result, "data_status", ignore.case = TRUE)
})

test_that("command_handler shows data-status guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "data-status", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

# =============================================================================
# Regstats Shiny output mode tests
# =============================================================================

test_that("command_handler handles regstats shiny output mode", {
  skip_if_no_command_handler()
  skip_if_not(exists("get_reg_stats", mode = "function"),
              "get_reg_stats not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")
  skip_if_not(exists("courses", envir = .GlobalEnv),
              "courses data not loaded")
  skip_if_not(exists("cedar_regstats_thresholds", envir = .GlobalEnv),
              "cedar_regstats_thresholds not configured")
  skip_if_not(exists("cedar_base_dir", envir = .GlobalEnv),
              "cedar_base_dir not configured")

  opt <- create_test_opt(func = "regstats", output = "shiny")

  result <- command_handler(opt)

  expect_true(is.character(result))
  expect_match(result, "Regstats dashboard data", ignore.case = TRUE)

  # Verify file was created
  output_file <- file.path(cedar_base_dir, "data", "regstats_dashboard.rds")
  expect_true(file.exists(output_file))
})

# =============================================================================
# Lookout tests
# =============================================================================

test_that("command_handler shows lookout guide", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "lookout", guide = TRUE)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to lookout with course param", {
  skip_if_no_command_handler()
  skip_if_not(exists("lookout", mode = "function"),
              "lookout not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")

  opt <- create_test_opt(func = "lookout", course = "ENGL 1120")

  result <- command_handler(opt)

  expect_true(is.null(result) || is.character(result))
})

# =============================================================================
# Seatfinder-report tests
# =============================================================================

test_that("command_handler shows seatfinder-report guide when no term", {
  skip_if_no_command_handler()

  opt <- create_test_opt(func = "seatfinder-report", guide = TRUE, term = NULL)

  expect_error(command_handler(opt), "no error")
})

test_that("command_handler routes to seatfinder-report with valid params", {
  skip_if_no_command_handler()
  skip_if_not(exists("create_seatfinder_report", mode = "function"),
              "create_seatfinder_report not available")
  skip_if_not(exists("students", envir = .GlobalEnv),
              "students data not loaded")
  skip_if_not(exists("courses", envir = .GlobalEnv),
              "courses data not loaded")

  opt <- create_test_opt(func = "seatfinder-report", term = "202380,202480")

  # Should complete without error
  result <- command_handler(opt)

  expect_true(is.null(result) || is.character(result))
})
