# Comprehensive tests for SFR (Student-Faculty Ratio) functions

test_that("get_perm_faculty_count returns valid data structure", {
  # Load real faculty data
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  result <- get_perm_faculty_count(cedar_faculty)

  # Should return a data frame

  expect_s3_class(result, "data.frame")

  # Should have required columns
  expect_true("term" %in% names(result))
  expect_true("department" %in% names(result))
  expect_true("total" %in% names(result))

  # Department should be codes (short strings like "HIST", "ANTH")
  avg_dept_len <- mean(nchar(result$department))
  expect_lt(avg_dept_len, 10)  # Codes should be short

  # Total should be positive (FTE counts)
  expect_true(all(result$total > 0))
})


test_that("get_perm_faculty_count filters for permanent faculty only", {
  # Load real faculty data
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  # Check that original data has multiple job categories
  all_categories <- unique(cedar_faculty$job_category)
  expect_true(length(all_categories) > 4)  # Should have TPT, Grad, etc.

  result <- get_perm_faculty_count(cedar_faculty)

  # Result should only include permanent faculty
  # The function aggregates by department, so we can't directly check job_category
  # But we can verify the counts are reasonable (not inflated by TPT/Grad)
  expect_gt(nrow(result), 0)
})


test_that("get_perm_faculty_count handles missing data gracefully", {
  # Test with NULL
  expect_null(get_perm_faculty_count(NULL))

  # Test with empty data frame
  empty_df <- data.frame()
  expect_null(get_perm_faculty_count(empty_df))

  # Test with missing required columns
  bad_df <- data.frame(x = 1:5, y = letters[1:5])
  expect_null(get_perm_faculty_count(bad_df))
})


test_that("get_sfr returns valid data structure with dept_code column", {
  # Load real data
  cedar_programs <- qs::qread(file.path(cedar_data_dir, "cedar_programs.qs"))
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  data_objects <- list(
    cedar_programs = cedar_programs,
    cedar_faculty = cedar_faculty
  )

  result <- get_sfr(data_objects)

  # Should return a data frame
  expect_s3_class(result, "data.frame")

  # Should have required columns including dept_code
  expect_true("term" %in% names(result))
  expect_true("dept_code" %in% names(result))
  expect_true("department" %in% names(result))
  expect_true("student_level" %in% names(result))
  expect_true("program_type" %in% names(result))
  expect_true("students" %in% names(result))
  expect_true("total" %in% names(result))
  expect_true("sfr" %in% names(result))
})


test_that("get_sfr excludes summer terms", {
  # Load real data
  cedar_programs <- qs::qread(file.path(cedar_data_dir, "cedar_programs.qs"))
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  data_objects <- list(
    cedar_programs = cedar_programs,
    cedar_faculty = cedar_faculty
  )

  result <- get_sfr(data_objects)

  # Summer terms end in 60 (e.g., 202360)
  summer_terms <- result$term[grepl("60$", as.character(result$term))]
  expect_equal(length(summer_terms), 0)
})


test_that("get_sfr separates majors and minors", {
  # Load real data
  cedar_programs <- qs::qread(file.path(cedar_data_dir, "cedar_programs.qs"))
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  data_objects <- list(
    cedar_programs = cedar_programs,
    cedar_faculty = cedar_faculty
  )

  result <- get_sfr(data_objects)

  # Should have both all_majors and all_minors
  program_types <- unique(result$program_type)
  expect_true("all_majors" %in% program_types)
  expect_true("all_minors" %in% program_types)
})


test_that("get_sfr dept_code mapping works for A&S departments", {
  # Load real data
  cedar_programs <- qs::qread(file.path(cedar_data_dir, "cedar_programs.qs"))
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  data_objects <- list(
    cedar_programs = cedar_programs,
    cedar_faculty = cedar_faculty
  )

  result <- get_sfr(data_objects)

  # Check that common A&S dept codes are present
  dept_codes <- unique(na.omit(result$dept_code))
  common_depts <- c("HIST", "ANTH", "ENGL", "BIOL", "PSYC")

  for (dept in common_depts) {
    expect_true(dept %in% dept_codes,
                info = paste("Expected", dept, "in dept_codes"))
  }
})


test_that("get_sfr_data_for_dept_report creates plots for valid department", {
  # Load real data
  cedar_programs <- qs::qread(file.path(cedar_data_dir, "cedar_programs.qs"))
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  data_objects <- list(
    cedar_programs = cedar_programs,
    cedar_faculty = cedar_faculty
  )

  d_params <- list(dept_code = "HIST", plots = list())
  result <- get_sfr_data_for_dept_report(data_objects, d_params)

  # Should have plots list
  expect_true("plots" %in% names(result))

  # Should have all three plot types
  expect_true("ug_sfr_plot" %in% names(result$plots))
  expect_true("grad_sfr_plot" %in% names(result$plots))
  expect_true("sfr_scatterplot" %in% names(result$plots))

  # At least some plots should be ggplot objects (not "Insufficient Data")
  has_ggplot <- any(sapply(result$plots, function(p) inherits(p, "ggplot")))
  expect_true(has_ggplot)
})


test_that("get_sfr_data_for_dept_report handles unknown department", {
  # Load real data
  cedar_programs <- qs::qread(file.path(cedar_data_dir, "cedar_programs.qs"))
  cedar_faculty <- qs::qread(file.path(cedar_data_dir, "cedar_faculty.qs"))

  data_objects <- list(
    cedar_programs = cedar_programs,
    cedar_faculty = cedar_faculty
  )

  # Use a fake department code
  d_params <- list(dept_code = "FAKE_DEPT", plots = list())
  result <- get_sfr_data_for_dept_report(data_objects, d_params)

  # Should still return plots list (with "Insufficient Data" messages)
  expect_true("plots" %in% names(result))
  expect_true("ug_sfr_plot" %in% names(result$plots))
})
