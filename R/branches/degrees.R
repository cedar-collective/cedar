#' Degree Analysis for CEDAR
#'
#' @description
#' This file contains functions for analyzing degree awards (graduates and pending graduates).
#' Functions count degrees awarded over time, broken down by major and degree type.
#'
#' Data comes from the Graduates and Pending Graduates Report and uses CEDAR naming conventions.
#'
#' @section Functions:
#'
#' **Core Functions:**
#' - `count_degrees()` - Count degrees awarded by term, major, and degree type
#' - `get_degrees_for_dept_report()` - Generate degree visualizations for department reports
#'
#' @section Data Requirements:
#'
#' **cedar_degrees table** (or degrees data from Graduates/Pending Graduates Report):
#' - `term` (integer) - Term code (e.g., 202580 for Fall 2025)
#' - `student_id` (string) - Encrypted student identifier
#' - `student_college` (string) - Student's college (e.g., "AS", "EN")
#' - `department` (string) - Department code (e.g., "MATH", "HIST")
#' - `program_code` (string) - Full Banner compound code (e.g., "BA-HIST-AS")
#' - `major_code` (string) - Catalog key matching major_dept_map$major_code (e.g., "HIST")
#' - `award_category` (string) - Award category (e.g., "Bachelor", "Master", "Doctoral")
#' - `degree` (string) - Degree type (e.g., "BA", "BS", "MA", "MS", "PhD")
#' - `major` (string) - Major name
#' - `second_major` (string, optional) - Second major name
#' - `first_minor` (string, optional) - First minor name
#' - `second_minor` (string, optional) - Second minor name
#'
#' @section Usage:
#'
#' ```r
#' # Load degrees data
#' degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))
#'
#' # Count degrees awarded
#' degree_counts <- count_degrees(degrees)
#'
#' # Generate department report visualizations
#' d_params <- list(
#'   term_start = 201980,
#'   term_end = 202580,
#'   prog_codes = c("Mathematics", "Applied Mathematics"),
#'   plots = list(),
#'   tables = list()
#' )
#' d_params <- get_degrees_for_dept_report(degrees, d_params)
#' ```
#'
#' @name degrees
NULL

#' Count Degrees Awarded
#'
#' @description
#' Counts degrees awarded by term and degree type for deduplication purposes.
#'
#' @param degrees_data Data frame with degree award data (CEDAR naming conventions).
#'   Must include columns: term, student_id, student_college, department,
#'   program_code, major_code, award_category, degree, major, second_major,
#'   first_minor, second_minor.
#'
#' @return Data frame with columns:
#'   - `term` (integer) - Term code
#'   - `major` (string) - Major name
#'   - `degree` (string) - Degree type (BA, BS, MA, MS, PhD, etc.)
#'   - `majors` (integer) - Count of degrees awarded
#'
#' @details
#' This function:
#' 1. Selects relevant columns from degrees data
#' 2. Removes duplicate rows (due to student attributes in source data)
#' 3. Counts degrees by term, major_code, and degree type
#'
#' The function intentionally does NOT filter by college to capture students from other
#' colleges who have an A&S program as a second major, certificate, etc.
#'
#' **Note:** Summarization uses `major_code` for grouping. Downstream filtering in
#' `get_degrees_for_dept_report()` filters by `major_code %in% prog_codes` to restrict
#' mappings.
#'
#' **TODO:** Currently optimized for A&S degrees. Make useful for all colleges.
#' **TODO:** Determine handling of minors, certificates, and other non-degree programs.
#'
#' @examples
#' \dontrun{
#' # Load degrees data
#' degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))
#'
#' # Count degrees awarded
#' degree_summary <- count_degrees(degrees)
#'
#' # View most recent term
#' degree_summary %>%
#'   filter(term == max(term)) %>%
#'   arrange(desc(majors))
#' }
#'
#' @export
count_degrees <- function(degrees_data) {

  # Don't filter by college here to get majors/minors from other colleges who have
  # an A&S program as a second major, certificate, etc.
  degrees_data <- degrees_data %>%
    select(term, student_college, student_id, department,
           program_code, major_code, award_category, degree, major,
           second_major, first_minor, second_minor)

  # Many degrees duplicated because of student attribute field from original data
  degrees_data <- unique(degrees_data)

  degree_summary <- degrees_data %>%
    group_by(term, major_code, degree) %>%
    summarize(majors = n(), .groups = 'drop')

  return(degree_summary)
}

#' Generate Degree Visualizations for Dept Trends
#'
#' @description
#' Prepares degree analysis data, plots, and tables for Dept Trends. Creates
#' visualizations showing degrees awarded over time, broken down by major and degree type.
#'
#' @param degrees_data Data frame with degree award data (CEDAR naming conventions).
#'   See `count_degrees()` for required columns.
#' @param dept_name Character. Department name for plot titles.
#' @param prog_codes Character vector. Program (major) codes to filter by (e.g., c("MATH", "AMAT")).
#' @param term_start Integer. Starting term code for filtering (e.g., 201980).
#' @param term_end Integer. Ending term code for filtering (e.g., 202580).
#' @param palette Character. ColorBrewer palette name for plots (e.g., "Set2").
#'
#' @return List with structure:
#'   list(
#'     plots  = list(degree_summary_faceted_by_major_plot, degree_summary_filtered_program_stacked_plot),
#'     tables = list(degree_summary_filtered_program)
#'   )
#'
#' @details
#' This function:
#' 1. Calls `count_degrees()` to get degree counts
#' 2. Filters by term range
#' 3. Filters by prog_codes (major_code)
#' 4. Creates faceted line chart (one facet per major)
#' 5. Creates stacked bar chart (aggregated across programs)
#'
#' Both plots are converted to interactive plotly objects for better exploration.
#'
#' @examples
#' \dontrun{
#' degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))
#' result <- get_degrees_for_dept_report(
#'   degrees,
#'   dept_name  = "Mathematics & Statistics",
#'   prog_codes = c("MATH", "AMAT"),
#'   prog_codes = c("Mathematics", "Applied Mathematics"),
#'   term_start = 201980,
#'   term_end   = 202580,
#'   palette    = "Set2"
#' )
#' result$plots$degree_summary_faceted_by_major_plot
#' result$tables$degree_summary_filtered_program
#' }
#'
#' @export
get_degrees_for_dept_report <- function(degrees_data, dept_name, prog_codes,
                                        term_start, term_end, palette) {
  message("[degrees.R] Welcome to get_degrees_for_dept_report!")

  degree_summary <- count_degrees(degrees_data)

  message("[degrees.R] Filtering degree summary by term...")
  degree_summary <- degree_summary %>%
    filter(as.integer(term) >= term_start & as.integer(term) <= term_end)

  message("[degrees.R] Grouping degree summary by term...")
  degree_summary <- degree_summary %>%
    group_by(term, major_code, degree) %>%
    summarize(majors = sum(majors), .groups = 'drop')

  message("[degrees.R] Filtering degree summary by program codes...")
  degree_summary_filtered <- degree_summary %>%
    filter(major_code %in% prog_codes)

  message("[degrees.R] Creating faceted line chart of degrees awarded...")
  if (nrow(degree_summary_filtered) > 0) {
    major_codes <- unique(degree_summary_filtered$major_code)
    sub_plots <- lapply(seq_along(major_codes), function(i) {
      mc  <- major_codes[[i]]
      df  <- degree_summary_filtered %>% filter(major_code == mc)
      plot_ly(df, x = ~as.character(term), y = ~majors, color = ~degree,
              colors      = palette,
              type        = "scatter", mode = "lines+markers",
              showlegend  = (i == 1),
              legendgroup = ~degree,
              hovertemplate = "%{x}<br>Degrees: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(
          annotations = list(list(
            text = mc, showarrow = FALSE,
            xref = "paper", yref = "paper", x = 0.5, y = 1.08,
            font = list(size = 12)
          )),
          xaxis = list(title = "Term", tickangle = -45),
          yaxis = list(title = "Degrees Awarded")
        )
    })
    degree_summary_faceted_by_major_plot <- subplot(
      sub_plots,
      nrows   = ceiling(length(major_codes) / 3),
      shareX  = FALSE, shareY  = FALSE,
      titleX  = TRUE,  titleY  = TRUE,
      margin  = 0.08
    ) %>% layout(legend = list(orientation = "h", x = 0, y = -0.15))
  } else {
    degree_summary_faceted_by_major_plot <- NULL
  }

  message("[degrees.R] Summarizing for degree type...")
  degree_summary_filtered_program <- degree_summary_filtered %>%
    group_by(term, degree) %>%
    summarize(majors_total = sum(majors), .groups = 'drop')

  plot_title <- paste(dept_name, ": ", paste(prog_codes, collapse = ", "))

  message("[degrees.R] Creating stacked bar chart of degrees awarded...")
  if (nrow(degree_summary_filtered_program) > 0) {
    degree_order <- degree_summary_filtered_program %>%
      group_by(degree) %>% summarise(tot = sum(majors_total), .groups = "drop") %>%
      arrange(tot) %>% pull(degree)
    degree_summary_filtered_program_stacked_plot <- plot_ly(
      degree_summary_filtered_program %>%
        mutate(term   = as.character(term),
               degree = factor(degree, levels = degree_order)),
      x             = ~term, y = ~majors_total, color = ~degree,
      colors        = palette,
      type          = "bar",
      hovertemplate = "%{x}<br>Degrees: %{y}<extra>%{fullData.name}</extra>"
    ) %>%
      layout(
        title   = list(text = plot_title, x = 0),
        barmode = "stack",
        xaxis   = list(title = "Term", tickangle = -45),
        yaxis   = list(title = "Degrees Awarded"),
        legend  = list(orientation = "h", x = 0, y = -0.2)
      )
  } else {
    degree_summary_filtered_program_stacked_plot <- NULL
  }

  message("[degrees.R] returning plots and tables...")
  list(
    plots = list(
      degree_summary_faceted_by_major_plot          = degree_summary_faceted_by_major_plot,
      degree_summary_filtered_program_stacked_plot  = degree_summary_filtered_program_stacked_plot
    ),
    tables = list(
      degree_summary_filtered_program = degree_summary_filtered_program,
      degree_summary_filtered         = degree_summary_filtered  # needed for faceted plot rebuild
    )
  )
}
