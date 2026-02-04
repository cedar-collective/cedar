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
#' - `program_code` (string) - Program code
#' - `award_category` (string) - Award category (e.g., "Bachelor", "Master", "Doctoral")
#' - `degree` (string) - Degree type (e.g., "BA", "BS", "MA", "MS", "PhD")
#' - `major` (string) - Major name
#' - `major_code` (string) - Major code
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
#'   prog_names = c("Mathematics", "Applied Mathematics"),
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
#' Counts degrees awarded by term, major, and degree type. Filters for relevant programs
#' using the major_to_program_map and handles both first and second majors.
#'
#' @param degrees_data Data frame with degree award data (CEDAR naming conventions).
#'   Must include columns: term, student_id, student_college, department,
#'   program_code, award_category, degree, major, major_code, second_major,
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
#' 3. Filters for programs defined in major_to_program_map
#' 4. Counts degrees by term, major, and degree type
#'
#' The function intentionally does NOT filter by college to capture students from other
#' colleges who have an A&S program as a second major, certificate, etc.
#'
#' **Note:** Summarization uses the `major` field rather than `major_code` to avoid
#' variations like "PSY" vs "PSYC". The major field is more reliable due to standardized
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
           program_code, award_category, degree, major, major_code,
           second_major, first_minor, second_minor)

  # Many degrees duplicated because of student attribute field from original data
  degrees_data <- unique(degrees_data)

  # Use pre-defined major_to_program_map to filter for just A&S degrees
  # TODO: make useful for all colleges
  programs <- names(major_to_program_map)

  # Get students who are graduating with a first or second major
  degrees_filtered <- degrees_data %>%
    filter(major %in% programs | second_major %in% programs)

  # TODO: what to do with minors / certificates / etc?

  # Summarize, but not using major_code (to avoid variations like PSY and PSYC)
  # The 'major' field is more reliable/standard because of mappings.
  degree_summary <- degrees_filtered %>%
    group_by(term, major, degree) %>%
    summarize(majors = n(), .groups = 'drop')

  return(degree_summary)
}

#' Generate Degree Visualizations for Department Report
#'
#' @description
#' Prepares degree analysis data, plots, and tables for department reports. Creates
#' visualizations showing degrees awarded over time, broken down by major and degree type.
#'
#' @param degrees_data Data frame with degree award data (CEDAR naming conventions).
#'   See `count_degrees()` for required columns.
#' @param d_params List containing department report parameters. Required fields:
#'   - `term_start` (integer) - Starting term code (e.g., 201980)
#'   - `term_end` (integer) - Ending term code (e.g., 202580)
#'   - `prog_names` (character vector) - Program names to include (e.g., c("Mathematics", "Physics"))
#'   - `prog_codes` (character vector) - Program codes for plot titles
#'   - `dept_name` (string) - Department name for plot titles
#'   - `palette` (string) - ColorBrewer palette name for plots
#'   - `plots` (list) - Existing plots list (will be updated)
#'   - `tables` (list) - Existing tables list (will be updated)
#'
#' @return Updated d_params list with new plots and tables added:
#'
#' **Plots added:**
#' - `degree_summary_faceted_by_major_plot` - Faceted line chart showing degrees awarded
#'   over time for each major/degree type combination
#' - `degree_summary_filtered_program_stacked_plot` - Stacked bar chart showing total
#'   degrees awarded by degree type across all programs
#'
#' **Tables added:**
#' - `degree_summary_filtered_program` - Summary table with columns: term, degree,
#'   majors_total
#'
#' @details
#' This function:
#' 1. Calls `count_degrees()` to get degree counts
#' 2. Filters by term range (term_start to term_end)
#' 3. Filters by program names from d_params
#' 4. Creates faceted line chart (one facet per major)
#' 5. Creates stacked bar chart (aggregated across programs)
#' 6. Adds plots and tables to d_params object
#'
#' **Visualizations:**
#' - **Faceted line chart**: Shows trends for each major separately, colored by degree type.
#'   Useful for seeing how individual programs grow/shrink over time.
#' - **Stacked bar chart**: Shows overall degree production by type, aggregated across
#'   all programs. Useful for seeing department-wide trends.
#'
#' Both plots are converted to interactive plotly objects for better exploration.
#'
#' @examples
#' \dontrun{
#' # Load data
#' degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))
#'
#' # Set up parameters
#' d_params <- list(
#'   term_start = 201980,
#'   term_end = 202580,
#'   prog_names = c("Mathematics", "Applied Mathematics"),
#'   prog_codes = c("MATH", "AMAT"),
#'   dept_name = "Mathematics & Statistics",
#'   palette = "Set2",
#'   plots = list(),
#'   tables = list()
#' )
#'
#' # Generate visualizations
#' d_params <- get_degrees_for_dept_report(degrees, d_params)
#'
#' # Access outputs
#' faceted_plot <- d_params$plots$degree_summary_faceted_by_major_plot
#' stacked_plot <- d_params$plots$degree_summary_filtered_program_stacked_plot
#' degree_table <- d_params$tables$degree_summary_filtered_program
#' }
#'
#' @export
get_degrees_for_dept_report <- function(degrees_data, d_params) {
  message("[degrees.R] Welcome to get_degrees_for_dept_report!")

  # Get degrees data
  degrees <- degrees_data

  degree_summary <- count_degrees(degrees)

  # Filter term according to input params
  message("[degrees.R] Filtering degree summary by term...")
  degree_summary <- degree_summary %>%
    filter(as.integer(term) >= d_params$term_start & as.integer(term) <= d_params$term_end)

  # Group by term instead of acad_year
  message("[degrees.R] Grouping degree summary by term...")
  degree_summary <- degree_summary %>%
    group_by(term, major, degree) %>%
    summarize(majors = sum(majors), .groups = 'drop')

  # Filter by d_params prog_names
  message("[degrees.R] Filtering degree summary by program names...")
  degree_summary_filtered <- degree_summary %>%
    filter(major %in% d_params$prog_names)

  # Create LINE CHART, faceted by MAJOR of degrees awarded over time
  # Facets only appear when a program has multiple programs
  message("[degrees.R] Creating faceted line chart of degrees awarded...")
  if (nrow(degree_summary_filtered) > 0) {
    degree_summary_faceted_by_major_plot <- ggplot(degree_summary_filtered,
                                                    aes(x = term, y = majors, col = degree)) +
      theme(legend.position = "bottom") +
      guides(color = guide_legend(title = "")) +
      geom_line(aes(group = degree)) +
      geom_point(aes(group = degree), alpha = .8) +
      facet_wrap(~major, ncol = 3) +
      scale_color_brewer(palette = d_params$palette) +
      xlab("Term") + ylab("Degrees Awarded")
    # Convert to plotly
    degree_summary_faceted_by_major_plot <- ggplotly(degree_summary_faceted_by_major_plot)
  } else {
    degree_summary_faceted_by_major_plot <- NULL
  }

  d_params$plots[["degree_summary_faceted_by_major_plot"]] <- degree_summary_faceted_by_major_plot


  # Summarize just for degree type (ignore program)
  message("[degrees.R] Summarizing for degree type...")
  degree_summary_filtered_program <- degree_summary_filtered %>%
    group_by(term, degree) %>%
    summarize(majors_total = sum(majors), .groups = 'drop')

  d_params$tables[["degree_summary_filtered_program"]] <- degree_summary_filtered_program


  # Prep plot title
  progs <- paste(d_params$prog_codes, collapse = ", ")
  plot_title <- paste(d_params$dept_name, ": ", progs)

  message("[degrees.R] Creating stacked bar chart of degrees awarded...")
  if (nrow(degree_summary_filtered_program) > 0) {
    degree_summary_filtered_program_stacked_plot <- degree_summary_filtered_program %>%
      mutate(degree = fct_reorder(degree, majors_total)) %>%
      ggplot(aes(x = term, y = majors_total, fill = degree)) +
      ggtitle(plot_title) +
      theme(legend.position = "bottom") +
      guides(color = guide_legend(title = "")) +
      geom_bar(position = "stack", stat = "identity") +
      scale_fill_brewer(palette = d_params$palette, limits = unique(degree_summary_filtered_program$degree)) +
      xlab("Term") + ylab("Degrees Awarded")
    # Convert to plotly
    degree_summary_filtered_program_stacked_plot <- ggplotly(degree_summary_filtered_program_stacked_plot)
  } else {
    degree_summary_filtered_program_stacked_plot <- NULL
  }

  d_params$plots[["degree_summary_filtered_program_stacked_plot"]] <- degree_summary_filtered_program_stacked_plot

  message("[degrees.R] returning d_params with new plot(s) and table(s)...")
  return(d_params)
}
