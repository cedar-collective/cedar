# Tests for plotly chart functions used by Dept Trends support
#
# Verifies that all functions converted from ggplot to native plotly return
# plotly objects with the expected trace types and shapes. Uses designed test
# fixtures (test_sections, test_students, test_programs, test_degrees,
# test_faculty) defined in setup.R / fixtures/designed_test_data.R.
#
# Known fixture values used here:
#   HIST: 5 total BA degrees across all terms (202060×2, 202080×2, 202110×1)
#   HIST dept headcount 202010: 64 students (25 pre-major + 39 declared)
#   HIST lower-div HIST 1110 202010: dfw_pct = 43.33
#   test_faculty covers ANTH, BIOL, ENGL, HIST, MATH, NURS, PSYC (28 rows)

context("Dept Trends Support Plots (plotly)")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_plotly <- function(x) inherits(x, "plotly")

any_plotly <- function(plot_list) any(sapply(plot_list, is_plotly))

# Use plotly_build() to force trace evaluation before inspecting internals.
# Without it, x/y/type fields may be unevaluated formulas or NULL.
built_data <- function(p) plotly_build(p)$x$data

trace_types <- function(p) unique(sapply(built_data(p), function(t) t$type))

all_x_values <- function(p) unlist(lapply(built_data(p), function(t) t$x))

all_y_values <- function(p) unlist(lapply(built_data(p), function(t) t$y))


# ===========================================================================
# get_degrees_for_dept_report() — plotly output
# ===========================================================================

test_that("get_degrees_for_dept_report scatter plot is plotly", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  p <- result$plots$degree_summary_faceted_by_major_plot
  expect_true(is_plotly(p),
              info = "degree_summary_faceted_by_major_plot should be a plotly object")
})

test_that("get_degrees_for_dept_report stacked bar is plotly", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  p <- result$plots$degree_summary_filtered_program_stacked_plot
  expect_true(is_plotly(p),
              info = "degree_summary_filtered_program_stacked_plot should be a plotly object")
})

test_that("get_degrees_for_dept_report stacked bar has bar trace type", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  p <- result$plots$degree_summary_filtered_program_stacked_plot
  expect_true("bar" %in% trace_types(p),
              info = "stacked degrees plot should contain bar traces")
})

test_that("get_degrees_for_dept_report stacked bar y values sum to 5 for HIST BA", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  p <- result$plots$degree_summary_filtered_program_stacked_plot
  total <- sum(all_y_values(p), na.rm = TRUE)
  expect_equal(total, 5L,
               info = "HIST has 5 total BA degrees in fixture data across all terms")
})

test_that("get_degrees_for_dept_report returns NULL plots for unknown prog_codes", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "Fake",
    prog_codes = "FAKE",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  expect_null(result$plots$degree_summary_faceted_by_major_plot)
  expect_null(result$plots$degree_summary_filtered_program_stacked_plot)
})


# ===========================================================================
# get_enrl_for_dept_report() — plotly output
# ===========================================================================

test_that("get_enrl_for_dept_report returns three plotly plots for HIST", {
  result <- get_enrl_for_dept_report(
    test_sections,
    dept_code  = "HIST",
    palette    = cedar_report_palette,
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term
  )
  expect_true(is_plotly(result$plots$highest_total_enrl_plot))
  expect_true(is_plotly(result$plots$highest_mean_enrl_plot))
  expect_true(is_plotly(result$plots$highest_mean_histo_plot))
})

test_that("get_enrl_for_dept_report bar plots use horizontal orientation", {
  result <- get_enrl_for_dept_report(
    test_sections,
    dept_code  = "HIST",
    palette    = cedar_report_palette,
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term
  )
  p <- result$plots$highest_total_enrl_plot
  orientations <- sapply(p$x$data, function(t) t$orientation)
  expect_true(all(orientations == "h"),
              info = "total enrollment bar plot should be horizontal")
})

test_that("get_enrl_for_dept_report histogram uses histogram trace type", {
  result <- get_enrl_for_dept_report(
    test_sections,
    dept_code  = "HIST",
    palette    = cedar_report_palette,
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term
  )
  p <- result$plots$highest_mean_histo_plot
  expect_true("histogram" %in% trace_types(p),
              info = "mean enrollment histogram should have histogram trace type")
})

test_that("get_enrl_for_dept_report returns tables with enrl_summary", {
  result <- get_enrl_for_dept_report(
    test_sections,
    dept_code  = "HIST",
    palette    = cedar_report_palette,
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term
  )
  expect_true("enrl_summary" %in% names(result$tables))
  expect_true(nrow(result$tables$enrl_summary) > 0)
})


# ===========================================================================
# get_headcount_data_for_dept_report() → make_headcount_plots_by_level()
# ===========================================================================

test_that("get_headcount_data_for_dept_report plots are plotly for HIST", {
  result <- get_headcount_data_for_dept_report(
    test_programs,
    dept_code  = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    lookups    = test_lookups
  )
  non_null_plots <- Filter(is_plotly, result$plots)
  expect_true(length(non_null_plots) > 0,
              info = "At least one headcount plot should be a plotly object for HIST")
})

test_that("make_headcount_plot returns plotly for simple summarized data", {
  # Build a minimal summarized tibble — no program_type column (simplest path)
  summarized <- tibble::tibble(
    term          = c(202010L, 202080L, 202010L, 202080L),
    student_count = c(20L, 22L, 5L, 6L),
    program_type  = c("Major", "Major", "First Minor", "First Minor")
  )
  p <- make_headcount_plot(summarized)
  expect_true(is_plotly(p),
              info = "make_headcount_plot should return a plotly object")
  expect_true("bar" %in% trace_types(p))
})

test_that("make_headcount_plot returns NULL for empty data", {
  empty <- tibble::tibble(
    term = integer(), student_count = integer(), program_type = character()
  )
  p <- make_headcount_plot(empty)
  expect_null(p)
})


# ===========================================================================
# plot_college_credit_hours()
# ===========================================================================

test_that("plot_college_credit_hours returns a plotly bar chart", {
  ch_data <- tibble::tibble(
    term        = c(202010L, 202010L, 202080L, 202080L),
    department  = c("HIST", "ANTH", "HIST", "ANTH"),
    total_hours = c(800L, 600L, 850L, 620L)
  )
  p <- plot_college_credit_hours(ch_data)
  expect_true(is_plotly(p))
  expect_true("bar" %in% trace_types(p))
})

test_that("plot_college_credit_hours y values match input totals", {
  ch_data <- tibble::tibble(
    term        = c(202010L, 202010L),
    department  = c("HIST", "ANTH"),
    total_hours = c(800L, 600L)
  )
  p <- plot_college_credit_hours(ch_data)
  total <- sum(all_y_values(p), na.rm = TRUE)
  expect_equal(total, 1400L)
})


# ===========================================================================
# plot_chd_by_subj_stacked()
# ===========================================================================

test_that("plot_chd_by_subj_stacked returns a plotly bar chart", {
  data <- tibble::tibble(
    term         = c(202010L, 202010L, 202080L, 202080L),
    subject_code = c("HIST", "ANTH", "HIST", "ANTH"),
    total_hours  = c(400L, 300L, 420L, 310L)
  )
  p <- plot_chd_by_subj_stacked(data)
  expect_true(is_plotly(p))
  expect_true("bar" %in% trace_types(p))
})


# ===========================================================================
# plot_chd_by_level()
# ===========================================================================

test_that("plot_chd_by_level returns a plotly stacked bar chart", {
  data <- tibble::tibble(
    term        = c(202010L, 202010L, 202080L, 202080L),
    level       = c("lower", "upper", "lower", "upper"),
    total_hours = c(600L, 200L, 620L, 210L)
  )
  p <- plot_chd_by_level(data, subj_codes = "HIST", palette = "Set2")
  expect_true(is_plotly(p))
  expect_true("bar" %in% trace_types(p))
  expect_equal(sum(all_y_values(p), na.rm = TRUE), 1630L)
})


# ===========================================================================
# Credit-hour Dept Trends builders
# ===========================================================================

test_that("get_credit_hours scoped summary matches relevant full summary", {
  dept_code <- "HIST"
  dept_college <- infer_credit_hours_dept_college(
    test_students,
    dept_code,
    cedar_report_start_term,
    cedar_report_end_term
  )

  full_relevant <- get_credit_hours(test_students) %>%
    filter(
      term >= cedar_report_start_term,
      term <= cedar_report_end_term,
      department == dept_code | college == dept_college
    ) %>%
    ungroup() %>%
    arrange(term, campus, college, department, subject_code, level)

  scoped <- get_credit_hours(
    test_students,
    term_start = cedar_report_start_term,
    term_end = cedar_report_end_term,
    departments = dept_code,
    colleges = dept_college
  ) %>%
    ungroup() %>%
    arrange(term, campus, college, department, subject_code, level)

  expect_equal(scoped, full_relevant, ignore_attr = TRUE)
})

test_that("get_credit_hours_for_dept_trends returns level-wide period table", {
  result <- get_credit_hours_for_dept_trends(
    test_students,
    dept_code = "HIST",
    subj_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end = cedar_report_end_term,
    palette = "Set2"
  )

  tbl <- result$tables$chd_by_period_table
  expect_true(is.data.frame(tbl))
  expect_false("level" %in% names(tbl))
  expect_true(all(c("term", "department", "subject_code", "total") %in% names(tbl)))

  level_cols <- intersect(c("lower", "upper", "grad"), names(tbl))
  expect_gt(length(level_cols), 0)
  expect_equal(tbl$total, rowSums(tbl[level_cols], na.rm = TRUE))
})


# ===========================================================================
# plot_chd_by_fac_faceted() and plot_chd_by_fac_stacked()
# ===========================================================================

test_that("plot_chd_by_fac_faceted returns a plotly object with bar traces", {
  data <- tibble::tibble(
    term         = rep(c(202010L, 202080L), 4),
    level        = rep(c("lower", "upper"), each = 4),
    job_category = rep(c("TT", "NTT"), 4),
    total_hours  = c(300L, 250L, 280L, 260L, 200L, 180L, 195L, 175L)
  )
  p <- plot_chd_by_fac_faceted(data, subj_codes = "HIST", palette = "Set2")
  expect_true(is_plotly(p))
  expect_true("bar" %in% trace_types(p))
})

test_that("plot_chd_by_fac_faceted returns string for empty data", {
  empty <- tibble::tibble(
    term = integer(), level = character(),
    job_category = character(), total_hours = integer()
  )
  result <- plot_chd_by_fac_faceted(empty, subj_codes = "HIST", palette = "Set2")
  expect_true(is.character(result))
})

test_that("plot_chd_by_fac_stacked returns a plotly bar chart", {
  data <- tibble::tibble(
    term         = c(202010L, 202010L, 202080L, 202080L),
    job_category = c("TT", "NTT", "TT", "NTT"),
    total_hours  = c(500L, 300L, 520L, 310L)
  )
  p <- plot_chd_by_fac_stacked(data, subj_codes = "HIST", palette = "Set2")
  expect_true(is_plotly(p))
  expect_true("bar" %in% trace_types(p))
})


# ===========================================================================
# Retired legacy Dept Report DFW entry point
# ===========================================================================

test_that("get_grades_for_dept_report stops with retired message", {
  expect_error(
    get_grades_for_dept_report(
      test_students,
      cedar_faculty = test_faculty,
      dept_code = "HIST"
    ),
    regexp = "get_grades_for_dept_report\\(\\) is retired"
  )
})


# ===========================================================================
# get_sfr_data_for_dept_report() — verify NOT ggplot (was failing after conversion)
# ===========================================================================

test_that("get_sfr_data_for_dept_report plots are plotly not ggplot for HIST", {
  do     <- list(cedar_programs = test_programs, cedar_faculty = test_faculty)
  result <- get_sfr_data_for_dept_report(do, "HIST")
  has_plotly <- any_plotly(result$plots)
  has_ggplot <- any(sapply(result$plots, function(p) inherits(p, "ggplot")))
  expect_true(has_plotly,
              info = "At least one SFR plot should be a plotly object")
  expect_false(has_ggplot,
               info = "No SFR plot should be a ggplot after conversion")
})
