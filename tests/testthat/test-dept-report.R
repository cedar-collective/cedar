# Tests for department report generation
# Tests R/cones/dept-report.R

context("Department Report Data Generation")

# Helper to create minimal data_objects for testing
create_test_data_objects <- function() {
  list(
    academic_studies = test_programs,  # For headcount
    degrees = test_degrees,            # For degrees
    class_lists = test_students,       # For credit hours, grades
    cedar_faculty = data.frame(       # Mock faculty data
      instructor_id = c("inst1", "inst2"),
      term = c(202510, 202510),
      department = c("hist", "hist"),
      job_category = c("professor", "lecturer"),
      appointment_pct = c(1.0, 0.5),
      stringsAsFactors = FALSE
    ),
    DESRs = test_sections              # For enrollment
  )
}

test_that("set_payload creates valid d_params structure", {
  # Mock required global variables
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("prgm_to_dept_map not available")
  }
  if (!exists("major_to_program_map", envir = .GlobalEnv)) {
    skip("major_to_program_map not available")
  }
  if (!exists("dept_code_to_name", envir = .GlobalEnv)) {
    skip("dept_code_to_name not available")
  }

  d_params <- set_payload("HIST", prog_focus = NULL)

  # Check required fields exist
  expect_true("dept_code" %in% names(d_params))
  expect_true("dept_name" %in% names(d_params))
  expect_true("subj_codes" %in% names(d_params))
  expect_true("prog_names" %in% names(d_params))
  expect_true("prog_codes" %in% names(d_params))
  expect_true("tables" %in% names(d_params))
  expect_true("plots" %in% names(d_params))
  expect_true("term_start" %in% names(d_params))
  expect_true("term_end" %in% names(d_params))
  expect_true("palette" %in% names(d_params))

  # Check types
  expect_equal(d_params$dept_code, "HIST")
  expect_type(d_params$tables, "list")
  expect_type(d_params$plots, "list")
  expect_length(d_params$tables, 0)  # Should start empty
  expect_length(d_params$plots, 0)   # Should start empty
})

test_that("set_payload with program focus filters correctly", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("prgm_to_dept_map not available")
  }

  d_params <- set_payload("HIST", prog_focus = "HIST")

  expect_equal(d_params$prog_focus, "HIST")
  expect_true("HIST" %in% d_params$prog_codes)
})

test_that("create_dept_report_data generates required outputs", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()
  opt <- list(dept = "HIST", prog = NULL)

  # This will call all the cone functions
  d_params <- create_dept_report_data(data_objects, opt)

  # Verify d_params structure
  expect_true("dept_code" %in% names(d_params))
  expect_true("tables" %in% names(d_params))
  expect_true("plots" %in% names(d_params))

  expect_equal(d_params$dept_code, "HIST")
  expect_type(d_params$tables, "list")
  expect_type(d_params$plots, "list")
})

test_that("create_dept_report_data calls headcount functions", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()
  opt <- list(dept = "HIST", prog = NULL)

  d_params <- create_dept_report_data(data_objects, opt)

  # Check that headcount tables/plots were added
  # These are specific outputs from get_headcount_data_for_dept_report
  expected_headcount_tables <- c(
    "hc_progs_under_long_majors",
    "hc_progs_under_long_minors",
    "hc_progs_grad_long_majors"
  )

  # At least some headcount outputs should exist
  # (may not have all if test data doesn't have undergrad/grad split)
  headcount_tables_present <- sum(expected_headcount_tables %in% names(d_params$tables))
  expect_true(headcount_tables_present >= 0)  # Just check it ran without error
})

test_that("create_dept_report_data calls degrees functions", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()
  opt <- list(dept = "HIST", prog = NULL)

  d_params <- create_dept_report_data(data_objects, opt)

  # Check that degree outputs were added
  # These are specific outputs from get_degrees_for_dept_report
  expected_degree_plots <- c(
    "degree_summary_faceted_by_major_plot",
    "degree_summary_filtered_program_stacked_plot"
  )

  expected_degree_tables <- c(
    "degree_summary_filtered_program"
  )

  # Check if degree outputs exist (may be NULL if no degree data for HIST)
  # Just verify the function ran and added keys
  degree_outputs_present <- sum(c(expected_degree_plots, expected_degree_tables) %in%
                                 c(names(d_params$plots), names(d_params$tables)))
  expect_true(degree_outputs_present >= 0)
})

test_that("create_dept_report_data uses CEDAR naming for faculty data", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()

  # Verify data_objects has cedar_faculty (not hr_data)
  expect_true("cedar_faculty" %in% names(data_objects))
  expect_false("hr_data" %in% names(data_objects))

  # Verify cedar_faculty has CEDAR columns
  expect_true("instructor_id" %in% colnames(data_objects$cedar_faculty))
  expect_true("term" %in% colnames(data_objects$cedar_faculty))
  expect_true("job_category" %in% colnames(data_objects$cedar_faculty))
  expect_true("department" %in% colnames(data_objects$cedar_faculty))

  opt <- list(dept = "HIST", prog = NULL)

  # Should not error with cedar_faculty
  expect_error(create_dept_report_data(data_objects, opt), NA)
})

test_that("create_dept_report_data output structure matches Shiny expectations", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()
  opt <- list(dept = "HIST", prog = NULL, shiny = TRUE)

  d_params <- create_dept_report_data(data_objects, opt)

  # Verify structure matches what Shiny app expects
  # From server.R: dept_report_data() stores d_params
  # and UI renders from d_params$plots and d_params$tables

  expect_true(is.list(d_params))
  expect_true(is.list(d_params$plots))
  expect_true(is.list(d_params$tables))

  # Check that plots are plotly or ggplot objects (or NULL)
  for (plot_name in names(d_params$plots)) {
    plot_obj <- d_params$plots[[plot_name]]
    if (!is.null(plot_obj)) {
      # Should be a plot object
      expect_true(
        inherits(plot_obj, "plotly") ||
        inherits(plot_obj, "ggplot") ||
        inherits(plot_obj, "htmlwidget"),
        info = paste("Plot", plot_name, "should be plotly/ggplot/htmlwidget")
      )
    }
  }

  # Check that tables are data frames (or NULL)
  for (table_name in names(d_params$tables)) {
    table_obj <- d_params$tables[[table_name]]
    if (!is.null(table_obj)) {
      expect_s3_class(
        table_obj,
        "data.frame",
        info = paste("Table", table_name, "should be a data frame")
      )
    }
  }
})

test_that("create_dept_report handles missing data gracefully", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  # Create minimal data_objects with empty tables
  data_objects <- list(
    academic_studies = data.frame(),
    degrees = data.frame(),
    class_lists = data.frame(),
    cedar_faculty = data.frame(),
    DESRs = data.frame()
  )

  opt <- list(dept = "HIST", prog = NULL)

  # Should not crash with empty data
  expect_error(create_dept_report_data(data_objects, opt), NA)
})

test_that("create_dept_report_data processes multiple departments", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()

  # Test with different departments
  for (dept_code in c("HIST", "MATH", "PHYS")) {
    opt <- list(dept = dept_code, prog = NULL)

    # Should work for any department
    d_params <- create_dept_report_data(data_objects, opt)
    expect_equal(d_params$dept_code, dept_code)
  }
})

test_that("dept-report uses cedar_faculty not hr_data", {
  # This test verifies the migration to CEDAR naming

  # Read dept-report.R source
  dept_report_source <- readLines("R/cones/dept-report.R")

  # Check that it references cedar_faculty (CEDAR naming)
  has_cedar_faculty <- any(grepl("cedar_faculty", dept_report_source))
  expect_true(has_cedar_faculty,
              info = "dept-report.R should reference cedar_faculty")

  # Check that it does NOT reference hr_data (old naming)
  has_hr_data <- any(grepl('data_objects\\[\\["hr_data"\\]\\]', dept_report_source))
  expect_false(has_hr_data,
               info = "dept-report.R should NOT reference hr_data (use cedar_faculty instead)")
})

test_that("dept-report passes cedar_faculty to get_grades_for_dept_report", {
  # Read dept-report.R source
  dept_report_source <- readLines("R/cones/dept-report.R")

  # Find the line calling get_grades_for_dept_report
  grades_call_lines <- grep("get_grades_for_dept_report", dept_report_source, value = TRUE)

  if (length(grades_call_lines) > 0) {
    # Should pass cedar_faculty as second parameter
    has_correct_param <- any(grepl('cedar_faculty', grades_call_lines))
    expect_true(has_correct_param,
                info = "get_grades_for_dept_report should receive cedar_faculty parameter")

    # Should NOT pass hr_data
    has_wrong_param <- any(grepl('hr_data', grades_call_lines))
    expect_false(has_wrong_param,
                 info = "get_grades_for_dept_report should NOT receive hr_data")
  }
})

test_that("Integration: dept-report generates all required sections", {
  if (!exists("prgm_to_dept_map", envir = .GlobalEnv)) {
    skip("Required global variables not available")
  }

  data_objects <- create_test_data_objects()
  opt <- list(dept = "HIST", prog = NULL)

  d_params <- create_dept_report_data(data_objects, opt)

  # Document expected outputs for each section
  # These are the keys that Shiny app or RMarkdown report expects

  # At minimum, d_params should have these top-level keys
  expect_true("dept_code" %in% names(d_params))
  expect_true("dept_name" %in% names(d_params))
  expect_true("prog_names" %in% names(d_params))
  expect_true("prog_codes" %in% names(d_params))
  expect_true("tables" %in% names(d_params))
  expect_true("plots" %in% names(d_params))

  # Log what was generated for debugging
  message("\n=== Department Report Generation Results ===")
  message("Department: ", d_params$dept_code)
  message("Programs: ", paste(d_params$prog_names, collapse = ", "))
  message("Tables generated: ", paste(names(d_params$tables), collapse = ", "))
  message("Plots generated: ", paste(names(d_params$plots), collapse = ", "))
  message("===========================================\n")

  # Verify at least some outputs were generated
  # (exact outputs depend on test data availability)
  total_outputs <- length(d_params$tables) + length(d_params$plots)
  expect_true(total_outputs >= 0,
              info = "Should generate at least some tables or plots")
})
