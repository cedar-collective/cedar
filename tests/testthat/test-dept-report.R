# Tests for Dept Trends feature support.
# Tests R/features/dept-trends.R.
#
# What IS testable without globals:
#   - Upfront input validation in create_dept_report_base()
#
# What requires refactoring to test:
#   - set_payload() reads globals; should accept maps as parameters
#
# All tests use test_* fixtures; no inline tibbles, no known_* data.

context("Dept Trends Support")

suppressPackageStartupMessages(library(shiny))
source(file.path(cedar_base_dir, "R", "modules", "ui-helpers.R"))
source(file.path(cedar_base_dir, "R", "modules", "dept-trends.R"))

# Helper: build a complete data_objects list from standard test fixtures.
make_data_objects <- function() {
  list(
    cedar_programs = test_programs,
    cedar_degrees  = test_degrees,
    cedar_students = test_students,
    cedar_faculty  = test_faculty,
    cedar_sections = test_sections,
    cedar_lookups  = test_lookups
  )
}


# =============================================================================
# Active base validation
# =============================================================================

test_that("create_dept_report_base stops on missing dataset key", {
  partial <- make_data_objects()
  partial[["cedar_programs"]] <- NULL

  expect_error(
    create_dept_report_base(partial, list(dept_code = "HIST")),
    regexp = "Missing required CEDAR datasets"
  )
})

test_that("create_dept_report_base stops when all required keys are missing", {
  expect_error(
    create_dept_report_base(list(), list(dept_code = "HIST")),
    regexp = "Missing required CEDAR datasets"
  )
})

test_that("Dept Trends base no longer requires unused faculty data", {
  data_objects <- make_data_objects()
  data_objects$cedar_faculty <- NULL

  expect_no_error(create_dept_report_base(
    data_objects,
    list(dept_code = "HIST", current_term = 202110L)
  ))
})

test_that("Dept Trends preloads every non-Gen-Ed analysis tab", {
  expect_identical(
    DEPT_TRENDS_PRELOAD_TABS,
    c("Enrollment", "Credit Hours", "Degrees", "Demographics")
  )

  specs <- lapply(DEPT_TRENDS_PRELOAD_TABS, dept_trends_tab_spec)
  expect_identical(vapply(specs, `[[`, character(1), "code"),
                   c("enrl", "ch", "deg", "demo"))

  loaded <- character(0)
  cache_hits <- preload_dept_trends_tabs(function(tab) {
    loaded <<- c(loaded, tab)
    tab != "Credit Hours"
  })
  expect_identical(loaded, DEPT_TRENDS_PRELOAD_TABS)
  expect_identical(
    unname(cache_hits),
    c(TRUE, FALSE, TRUE, TRUE)
  )
})

test_that("Dept Trends prepares tabs and Refresh bypasses every main-tab cache", {
  data_objects <- make_data_objects()
  data_objects$cedar_students <- data_objects$cedar_students %>%
    dplyr::mutate(major_name = major_code)
  errors <- character(0)
  headcount_writes <- 0L
  cached_base <- create_dept_report_base(
    data_objects, list(dept_code = "HIST", current_term = 202110L)
  )

  module_env <- new.env(parent = globalenv())
  sys.source(
    file.path(cedar_base_dir, "R", "modules", "dept-trends.R"),
    envir = module_env
  )
  module_env$deptProfileGenEdServer <- function(...) NULL
  module_env$load_dept_headcount_cache <- function(...) cached_base
  module_env$load_dept_tab_cache <- function(...) NULL
  module_env$cache_dept_headcount <- function(...) {
    headcount_writes <<- headcount_writes + 1L
    TRUE
  }
  module_env$cache_dept_tab <- function(...) TRUE
  module_env$write_log <- function(...) invisible(NULL)
  module_env$log_data_filter <- function(...) invisible(NULL)
  module_env$log_report_generation <- function(...) invisible(NULL)
  module_env$start_report_timer <- function(...) 0
  module_env$end_report_timer <- function(...) 0
  module_env$signal_load_start <- function(...) invisible(NULL)
  module_env$signal_load_complete <- function(...) invisible(NULL)

  suppressWarnings(shiny::testServer(
    module_env$deptTrendsServer,
    args = list(
      data_objects = data_objects,
      dept_choices = c(History = "HIST"),
      current_term = 202110L,
      error_handler = function(e, context) {
        errors <<- c(errors, paste(context, conditionMessage(e)))
      }
    ),
    {
      session$setInputs(campus = c("ABQ", "EA"))
      session$flushReact()
      session$setInputs(dept = "HIST")
      session$flushReact()

      expect_false(is.null(dept_data()))
      expect_false(is.null(enrl_data()))
      expect_false(is.null(ch_data()))
      expect_false(is.null(deg_data()))
      expect_false(is.null(demo_data()))
      expect_true(all(
        DEPT_TRENDS_CREDIT_HOUR_PLOTS %in% names(ch_data()$plots)
      ))
      expect_equal(headcount_writes, 0L)

      module_env$load_dept_headcount_cache <- function(...) stop("Refresh read Headcount cache")
      module_env$load_dept_tab_cache <- function(...) stop("Refresh read tab cache")
      session$setInputs(reload = 1L)
      session$flushReact()
      expect_equal(headcount_writes, 1L)
    }
  ))

  expect_length(errors, 0)
})

test_that("compute_dept_enrl_tab carries historical enrollment plots", {
  data_objects <- make_data_objects()
  data_objects$cedar_students <- data_objects$cedar_students %>%
    dplyr::mutate(major_name = major_code)
  base <- list(
    dept_code = "HIST",
    palette = "Set2",
    term_start = cedar_report_start_term,
    term_end = cedar_report_end_term,
    current_term = 202110L
  )

  result <- compute_dept_enrl_tab(base, data_objects)

  expect_true("enrl_history_by_level" %in% names(result$tables))
  expect_true(is.data.frame(result$tables$enrl_history_by_level))
  expect_true(all(c(
    "enrl_term_enrollment_plot", "enrl_term_sections_plot",
    "enrl_term_avg_size_plot", "enrl_gen_ed_college_context_plot",
    "enrl_cross_dept_minors", "enrl_majors_with_minor"
  ) %in% names(result$plots)))
})

test_that("Dept Trends data-only tab payloads rebuild their plots", {
  data_objects <- make_data_objects()
  data_objects$cedar_students <- data_objects$cedar_students %>%
    dplyr::mutate(major_name = major_code)
  base <- list(
    dept_code = "HIST",
    dept_name = "History",
    prog_codes = "HIST",
    subj_codes = "HIST",
    palette = NULL,
    term_start = cedar_report_start_term,
    term_end = cedar_report_end_term,
    current_term = 202110L
  )

  enrl <- compute_dept_enrl_tab(base, data_objects)
  enrl_rebuilt <- rebuild_dept_enrl_tab(enrl["tables"], base)
  expect_true(all(names(enrl$plots) %in% names(enrl_rebuilt$plots)))
  expect_true(all(vapply(
    enrl_rebuilt$tables$enrl_student_donuts$tables,
    function(x) !"color" %in% names(x),
    logical(1)
  )))

  degrees <- compute_dept_degrees_tab(base, data_objects)
  degrees_rebuilt <- rebuild_dept_degrees_tab(degrees["tables"], base)
  expect_equal(sort(names(degrees_rebuilt$plots)), sort(names(degrees$plots)))

  credit_hours <- compute_dept_credit_hours_tab(base, data_objects)
  expect_true(all(
    DEPT_TRENDS_CREDIT_HOUR_PLOTS %in% names(credit_hours$plots)
  ))
  expect_false(any(c(
    "chd_by_fac_facet_plot", "chd_by_fac_plot"
  ) %in% names(credit_hours$plots)))
  expect_null(credit_hours$tables$credit_hours_data_w)
  expect_null(credit_hours$plots$sch_outside_pct_plot)
  expect_null(credit_hours$plots$sch_dept_pct_plot)
  credit_hours_rebuilt <- rebuild_dept_credit_hours_tab(
    credit_hours["tables"], base
  )
  expect_equal(sort(names(credit_hours_rebuilt$plots)), sort(names(credit_hours$plots)))

  demographics <- compute_dept_demographics_tab(base, data_objects)
  demographics_rebuilt <- rebuild_dept_demographics_tab(
    demographics["tables"], base
  )
  expect_s3_class(demographics_rebuilt$plots$population_trend, "ggplot")
})

test_that("Dept Trends base rehydration does not retain live source tables", {
  cached_plot <- structure(list(source = "cache"), class = "plotly")
  cached <- list(
    dept_code = "HIST",
    dept_raw = "HIST",
    dept_name = "History",
    subj_codes = "HIST",
    prog_codes = "HIST",
    prog_focus = NULL,
    term_start = cedar_report_start_term,
    term_end = cedar_report_end_term,
    current_term = 202110L,
    plots = list(hc_progs_under_long_majors_plot = cached_plot),
    tables = list()
  )

  base <- rehydrate_dept_report_base(
    cached,
    list(current_term = 202110L, campus = c("ABQ", "EA"))
  )

  expect_false("data_objects_filt" %in% names(base))
  expect_identical(base$plots$hc_progs_under_long_majors_plot, cached_plot)
})

test_that("Dept Trends cached tabs reuse stored plots without rebuilding", {
  cached_plot <- structure(list(source = "cache"), class = "plotly")
  cached <- list(
    plots = list(example = cached_plot),
    tables = list(example = tibble::tibble(x = 1))
  )
  rebuild <- function(cached, base) {
    stop("ready cache payload should not rebuild")
  }

  payload <- rehydrate_dept_tab_payload(cached, list(), rebuild)

  expect_identical(payload$plots$example, cached_plot)
  expect_equal(payload$tables$example$x, 1)
})

test_that("Dept Trends rebuilds an incomplete cached plot payload", {
  cached <- list(
    plots = list(old_plot = structure(list(), class = "plotly")),
    tables = list(example = tibble::tibble(x = 1))
  )
  rebuilt_plot <- structure(list(source = "rebuilt"), class = "plotly")
  rebuild <- function(cached, base) {
    list(
      plots = list(required_plot = rebuilt_plot),
      tables = cached$tables
    )
  }

  payload <- rehydrate_dept_tab_payload(
    cached, list(), rebuild, required_plots = "required_plot"
  )

  expect_identical(payload$plots$required_plot, rebuilt_plot)
})

test_that("Credit Hours UI does not read its payload while building the tab shell", {
  expect_false("ch_data" %in% names(formals(deptTrendsCreditHoursUI)))

  html <- as.character(deptTrendsCreditHoursUI(NS("dept"), "HIST"))
  expected_ids <- paste0("dept-", DEPT_TRENDS_CREDIT_HOUR_PLOTS)
  expect_true(all(vapply(
    expected_ids,
    function(id) grepl(id, html, fixed = TRUE),
    logical(1)
  )))
  expect_match(html, "dept-sch_trends_lower", fixed = TRUE)
  expect_match(html, "dept-sch_trends_upper", fixed = TRUE)
})

test_that("credit-hour dept trends carry level-specific college comparisons", {
  result <- get_credit_hours_for_dept_trends(
    test_students,
    dept_code = "HIST",
    subj_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end = cedar_report_end_term,
    palette = "Set2"
  )

  expect_true(all(c(
    "college_dept_dual_plot",
    "college_dept_lower_dual_plot",
    "college_dept_upper_dual_plot",
    "college_dept_grad_dual_plot"
  ) %in% names(result$plots)))
})


# =============================================================================
# count_degrees() — unit tests (no globals required)
# =============================================================================

test_that("count_degrees returns a data frame with required columns", {
  result <- count_degrees(test_degrees)
  expect_true(is.data.frame(result))
  expect_true(all(c("term", "major_code", "degree", "majors") %in% names(result)),
              info = paste("Missing columns:", paste(setdiff(c("term","major_code","degree","majors"), names(result)), collapse=", ")))
})

test_that("count_degrees does not include a bare 'major' column", {
  result <- count_degrees(test_degrees)
  expect_false("major" %in% names(result),
               info = "count_degrees should group by major_code, not major name")
})

test_that("count_degrees returns correct degree counts for HIST", {
  result <- count_degrees(test_degrees)
  hist_rows <- result[result$major_code == "HIST" & result$degree == "BA", ]
  # Fixture: DEG001+DEG002 in 202060, DEG007 in 202080, DEG010 in 202110, DEG011 in 202080
  # → 202060: 2, 202080: 2 (DEG007 + DEG011), 202110: 1
  expect_equal(sum(hist_rows$majors), 5L,
               info = "Expected 5 total HIST BA degrees across all terms")
})

test_that("count_degrees handles data with no rows gracefully", {
  empty <- test_degrees[FALSE, ]
  result <- count_degrees(empty)
  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 0L)
})


# =============================================================================
# get_degrees_for_dept_report() — integration tests
# =============================================================================

test_that("get_degrees_for_dept_report returns list with plots and tables keys", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  expect_true(is.list(result))
  expect_true(all(c("plots", "tables") %in% names(result)))
})

test_that("get_degrees_for_dept_report tables contain major_code not major", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  deg_filtered <- result$tables$degree_summary_filtered
  expect_true("major_code" %in% names(deg_filtered),
              info = "degree_summary_filtered must have major_code column")
  expect_false("major" %in% names(deg_filtered),
               info = "degree_summary_filtered should not have a bare 'major' column")
})

test_that("get_degrees_for_dept_report filters to the requested prog_codes", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "History",
    prog_codes = "HIST",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  deg_filtered <- result$tables$degree_summary_filtered
  expect_true(all(deg_filtered$major_code == "HIST"),
              info = "All rows should have major_code == 'HIST'")
})

test_that("get_degrees_for_dept_report produces NULL plots when prog_codes has no matches", {
  result <- get_degrees_for_dept_report(
    test_degrees,
    dept_name  = "Nonexistent",
    prog_codes = "NOSUCH",
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = "Set2"
  )
  expect_null(result$plots$degree_summary_faceted_by_major_plot)
  expect_null(result$plots$degree_summary_filtered_program_stacked_plot)
  expect_equal(nrow(result$tables$degree_summary_filtered), 0L)
})
