#' Headcount: Student Program Enrollment Analysis
#'
#' This file contains functions for analyzing student enrollment by academic program
#' (majors, minors, concentrations) over time.
#'
#' @section Data Requirements:
#' Requires cedar_programs table with CEDAR column names (lowercase with underscores):
#' - student_id (encrypted student identifier)
#' - term (integer term code, e.g., 202580)
#' - student_campus (campus code)
#' - student_college (college code for student's primary college)
#' - student_level ("Undergraduate", "Graduate/GASM")
#' - degree (degree type)
#' - department (department code)
#' - program_type ("Major", "Second Major", "First Minor", "Second Minor", etc.)
#' - program_name (program name)
#' - program_code (program code, e.g., "MATH-BS")
#'
#' @section Main Functions:
#' - get_headcount(): Main orchestrating function for flexible headcount analysis
#' - get_headcount_data_for_dept_report(): Generate complete dept report data/plots
#' - make_headcount_plots_by_level(): Create separate UG/Grad plots
#' - make_headcount_plot(): Create single combined plot
#'
#' @section Helper Functions:
#' - filter_programs_by_opt(): Apply institutional and program filters
#' - summarize_headcount(): Group and count students
#' - format_headcount_result(): Package data with metadata
#'
#' @section Deprecated Functions:
#' - count_heads_by_program(): Deprecated wrapper, use get_headcount() instead
#'
#' @examples
#' \dontrun{
#' # Get headcount by department
#' opt <- list(dept = "MATH")
#' result <- get_headcount(cedar_programs, opt)
#'
#' # Get headcount with custom grouping (for SFR)
#' result <- get_headcount(
#'   cedar_programs,
#'   opt = list(),
#'   group_by = c("term", "department", "student_level")
#' )
#'
#' # Create plots
#' plots <- make_headcount_plots_by_level(result)
#' }
#'
#' @name headcount



#' Filter Programs Data by Options
#'
#' Helper function that applies institutional and program filters to CEDAR programs data.
#'
#' @param programs Data frame of student program enrollment data (CEDAR format)
#' @param opt Options list with possible filters:
#'   \itemize{
#'     \item campus - Vector of campus codes to include
#'     \item college - Vector of college codes to include
#'     \item dept - Vector of department codes to include
#'     \item major - Vector of major program names to include
#'     \item major_codes - Vector of major program codes to include (preferred over major for reliability).
#'                        Supports prefix matching: "HIST-BA", "HIST-MA" will also match minor code "HIST"
#'     \item minor - Vector of minor program names to include
#'     \item concentration - Vector of concentration names to include
#'   }
#'
#' @return List with:
#'   \describe{
#'     \item{data}{Filtered data frame}
#'     \item{has_program_filter}{Boolean indicating if program-specific filters were applied}
#'   }
#'
#' @details
#' Applies filters in two stages:
#' 1. Institutional filters (campus, college, department)
#' 2. Program filters (major, minor, concentration)
#'
#' Program filters are applied inclusively - they keep the specified programs
#' while preserving other program types for the same students.
#'
#' @keywords internal
filter_programs_by_opt <- function(programs, opt = list()) {

  # Select important columns (CEDAR naming)
  important_cols <- c("student_id", "term", "student_college", "student_campus",
                      "student_level", "degree", "department",
                      "program_type", "program_name")

  message("[headcount.R] Selecting CEDAR columns...")
  available_cols <- important_cols[important_cols %in% colnames(programs)]
  df <- programs %>% select(all_of(available_cols)) %>% distinct()
  message("[headcount.R] Data shape: ", nrow(df), " rows, ", ncol(df), " cols")

  # Apply filters
  if (!is.null(opt$campus) && length(opt$campus) > 0) {
    message("[headcount.R] Filtering by campus: ", paste(opt$campus, collapse = ", "))
    df <- df %>% filter(student_campus %in% opt$campus)
  }

  if (!is.null(opt$college) && length(opt$college) > 0) {
    message("[headcount.R] Filtering by college: ", paste(opt$college, collapse = ", "))
    df <- df %>% filter(student_college %in% opt$college)
  }

  # TODO: filtering by dept can hide minors if students major in another dept
  if (!is.null(opt$dept) && length(opt$dept) > 0) {
    message("[headcount.R] Filtering by department: ", paste(opt$dept, collapse = ", "))
    df <- df %>% filter(department %in% opt$dept)
  }

  # Track if program-specific filters were applied
  has_program_filter <- FALSE

  if (!is.null(opt$major) && length(opt$major) > 0) {
    message("[headcount.R] Filtering by major: ", paste(opt$major, collapse = ", "))
    df <- df %>% filter(
      (program_type %in% c("Major", "Second Major") & program_name %in% opt$major)
    )
    has_program_filter <- TRUE
  }

  if (!is.null(opt$minor) && length(opt$minor) > 0) {
    message("[headcount.R] Filtering by minor: ", paste(opt$minor, collapse = ", "))
    df <- df %>% filter(
      (program_type %in% c("First Minor", "Second Minor") & program_name %in% opt$minor)
    )
    has_program_filter <- TRUE
  }

  if (!is.null(opt$concentration) && length(opt$concentration) > 0) {
    message("[headcount.R] Filtering by concentration: ", paste(opt$concentration, collapse = ", "))
    df <- df %>% filter(program_type %in% c("First Concentration", "Second Concentration"))
    has_program_filter <- TRUE
  }

  message("[headcount.R] Data shape after filters: ", nrow(df), " rows")

  return(list(data = df, has_program_filter = has_program_filter))
}


#' Summarize Headcount Data
#'
#' Helper function that groups and counts students from filtered programs data.
#'
#' @param df Filtered programs data frame (from filter_programs_by_opt)
#' @param has_program_filter Boolean indicating if program filters were applied
#' @param group_by Character vector of column names to group by.
#'   Default: c("term", "student_level", "program_type", "program_name")
#'   For aggregate summaries, use: c("term", "student_level", "program_type")
#'
#' @return Data frame with columns based on group_by plus student_count
#'
#' @details
#' If no program filters were applied, summarizes by program type only.
#' If program filters were applied, includes program_name in grouping.
#'
#' @keywords internal
summarize_headcount <- function(df, has_program_filter, group_by = NULL) {

  # Determine grouping columns
  if (is.null(group_by)) {
    if (!has_program_filter) {
      message("[headcount.R] No program filters - summarizing by program type only")
      group_by <- c("term", "student_level", "program_type")
    } else {
      message("[headcount.R] Summarizing by specific programs")
      group_by <- c("term", "student_level", "program_type", "program_name")
    }
  } else {
    message("[headcount.R] Using custom grouping: ", paste(group_by, collapse = ", "))
  }

  # DEBUG: Check program_types before program_name filter
  message("[headcount.R] DEBUG - summarize_headcount input program_types: ",
          paste(names(table(df$program_type)), "=", table(df$program_type), collapse = ", "))

  # Check for NA/empty program_names by program_type
  na_or_empty <- df %>% filter(is.na(program_name) | program_name == "")
  if (nrow(na_or_empty) > 0) {
    message("[headcount.R] DEBUG - Records with NA/empty program_name by type: ",
            paste(names(table(na_or_empty$program_type)), "=", table(na_or_empty$program_type), collapse = ", "))
  }

  # Filter out empty program names and summarize
  summarized <- df %>%
    filter(!is.na(program_name) & program_name != "") %>%
    group_by(across(all_of(group_by))) %>%
    summarize(student_count = n_distinct(student_id), .groups = "drop") %>%
    arrange(across(all_of(group_by)))

  message("[headcount.R] DEBUG - summarized output program_types: ",
          paste(names(table(summarized$program_type)), "=", table(summarized$program_type), collapse = ", "))

  message("[headcount.R] Summary data shape: ", nrow(summarized), " rows")

  return(summarized)
}


#' Format Headcount Result with Metadata
#'
#' Helper function that packages headcount data with metadata.
#'
#' @param summarized Summarized headcount data frame
#' @param df Original filtered data (for metadata calculation)
#' @param has_program_filter Boolean indicating if program filters were applied
#' @param opt Options list used for filtering
#'
#' @return List with data and metadata:
#'   \describe{
#'     \item{data}{Summarized headcount data frame}
#'     \item{no_program_filter}{Boolean - TRUE if no program filters applied}
#'     \item{metadata}{List with total_students, programs_included, filters_applied}
#'   }
#'
#' @keywords internal
format_headcount_result <- function(summarized, df, has_program_filter, opt) {

  result <- list(
    data = summarized,
    no_program_filter = !has_program_filter,
    metadata = list(
      total_students = n_distinct(df$student_id),
      programs_included = if (!has_program_filter) "all" else c(opt$major, opt$minor, opt$concentration),
      filters_applied = names(opt)[!sapply(opt, is.null)]
    )
  )

  return(result)
}


#' Get Student Headcount
#'
#' Main function for calculating student headcount from CEDAR programs data.
#' Flexible orchestrating function that filters, summarizes, and packages
#' headcount data for various use cases.
#'
#' @param programs Student program enrollment data in CEDAR format.
#'   Required columns: student_id, term, student_level, program_type, program_name.
#'   Optional columns: student_college, student_campus, department, degree, program_code.
#' @param opt Options list for filtering and behavior:
#'   \itemize{
#'     \item campus - Filter by campus code(s)
#'     \item college - Filter by college code(s)
#'     \item dept - Filter by department code(s)
#'     \item major - Filter by major program name(s)
#'     \item major_codes - Filter by major program code(s) - PREFERRED over major for consistency.
#'                        Uses prefix matching to include related minors/programs (e.g., "HIST" matches "HIST-BA", "HIST-MA")
#'     \item minor - Filter by minor program name(s)
#'     \item concentration - Filter by concentration name(s)
#'   }
#' @param group_by Optional character vector of column names to group by.
#'   Default behavior groups by term, student_level, program_type, and program_name
#'   (if program filters applied) or just program_type (if no program filters).
#'   For custom aggregations (e.g., SFR), specify columns explicitly.
#'
#' @return List with headcount data and metadata:
#'   \describe{
#'     \item{data}{Data frame with student_count column and grouping columns}
#'     \item{no_program_filter}{Boolean indicating if program-specific filters were applied}
#'     \item{metadata}{List with total_students, programs_included, filters_applied}
#'   }
#'
#' @details
#' **CEDAR Data Model Only**
#'
#' This function requires CEDAR-formatted data with lowercase column names.
#' No fallbacks to legacy naming - CEDAR is mandatory.
#'
#' **Architecture:**
#'
#' This is an orchestrating function that delegates to smaller helper functions:
#' - \code{\link{filter_programs_by_opt}}: Applies filters
#' - \code{\link{summarize_headcount}}: Groups and counts
#' - \code{\link{format_headcount_result}}: Packages with metadata
#'
#' **Workflow:**
#' 1. Selects relevant CEDAR columns (student_id, term, program fields, etc.)
#' 2. Applies institutional filters (campus, college, department)
#' 3. Applies program filters (major, minor, concentration)
#' 4. Groups and counts unique students
#' 5. Returns structured result with metadata
#'
#' **Use Cases:**
#' - Department reports: Filter by dept/program, get detailed breakdown
#' - SFR calculations: Specify custom group_by for aggregated counts
#' - General headcount: No filters, get all programs
#'
#' **Deprecated Functions:**
#'
#' \code{count_heads_by_program()} is deprecated and now simply calls
#' \code{get_headcount()}. Update your code to use \code{get_headcount()} directly.
#'
#' @examples
#' \dontrun{
#' # Department report headcount (detailed)
#' result <- get_headcount(
#'   programs = cedar_programs,
#'   opt = list(dept = "HIST", major = "History")
#' )
#'
#' # SFR headcount (aggregated by term and dept)
#' result <- get_headcount(
#'   programs = cedar_programs,
#'   opt = list(),
#'   group_by = c("term", "department", "student_level")
#' )
#' }
#'
#' @seealso
#' Helper functions:
#' \code{\link{filter_programs_by_opt}},
#' \code{\link{summarize_headcount}},
#' \code{\link{format_headcount_result}}
#'
#' Related functions:
#' \code{\link{get_headcount_data_for_dept_report}},
#' \code{\link{make_headcount_plots_by_level}},
#' \code{\link{make_headcount_plot}}
#'
#' @export
get_headcount <- function(programs, opt = list(), group_by = NULL) {

  message("[headcount.R] Welcome to get_headcount!")
  message("[headcount.R] opt contents: ", paste(names(opt), collapse = ", "))

  # Step 1: Filter programs data
  filtered <- filter_programs_by_opt(programs, opt)

  # Step 2: Summarize headcount by specified groups
  summarized <- summarize_headcount(
    df = filtered$data,
    has_program_filter = filtered$has_program_filter,
    group_by = group_by
  )

  message("[headcount.R] Sample data (", nrow(summarized), " rows, columns: ", paste(names(summarized), collapse=", "), "):")
  message(paste(capture.output(print(head(summarized, 10))), collapse = "\n"))

  # Step 3: Format result with metadata
  result <- format_headcount_result(
    summarized = summarized,
    df = filtered$data,
    has_program_filter = filtered$has_program_filter,
    opt = opt
  )

  return(result)
}


#' Create Headcount Plots by Student Level
#'
#' Creates separate interactive plots for undergraduate and graduate students,
#' with appropriate visualization choices for each level.
#'
#' @param result Result list from count_heads_by_program() containing data and metadata
#'
#' @return Named list with plotly plots:
#'   \describe{
#'     \item{undergrad}{Undergraduate enrollment plot (stacked bars by program)}
#'     \item{graduate}{Graduate enrollment plot (dodged bars by program)}
#'   }
#'
#' @details
#' Undergraduate plots use stacked bars faceted by program for density.
#' Graduate plots use dodged bars for easier comparison of smaller cohorts.
#'
#' @export
make_headcount_plots_by_level <- function(result) {

  message("[headcount.R] Welcome to make_headcount_plots_by_level!")

  # Extract data and metadata
  summarized <- result$data
  no_program <- result$no_program_filter
  has_program_type <- "program_type" %in% colnames(summarized)

  plots <- list()

  # Convert term to factor with proper ordering for discrete x-axis
  summarized$term <- factor(summarized$term, levels = sort(unique(summarized$term)), ordered = TRUE)

  # Define program type ordering (academic hierarchy) - only if column exists
  if (has_program_type) {
    program_type_order <- c("Major", "Second Major", "First Minor", "Second Minor",
                           "First Concentration", "Second Concentration")
    summarized$program_type <- factor(summarized$program_type,
                                     levels = program_type_order,
                                     ordered = TRUE)
  }

  # Order program values alphabetically for consistent display
  if (!no_program && "program_name" %in% colnames(summarized)) {
    program_value_order <- sort(unique(summarized$program_name))
    summarized$program_name <- factor(summarized$program_name,
                                      levels = program_value_order,
                                      ordered = TRUE)
  }

  # Undergraduate plot (CEDAR naming)
  message("[headcount.R] Creating Undergraduate plot...")
  undergrad_data <- summarized[summarized$student_level == "Undergraduate", ]

  if (nrow(undergrad_data) > 0) {
    if (!has_program_type) {
      # Simple time series when no program_type breakdown
      p_undergrad <- ggplot(undergrad_data, aes(x = term, y = student_count)) +
        geom_bar(stat = "identity", fill = "steelblue") +
        labs(title = "Undergraduate Headcount", x = "Term", y = "Student Count") +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    } else if (!no_program && "program_name" %in% colnames(summarized)) {
      p_undergrad <- ggplot(undergrad_data, aes(x = term, y = student_count, fill = program_type)) +
        geom_bar(stat = "identity", position = "stack") +
        facet_wrap(~program_name, scales = "fixed", ncol = 2) +
        labs(title = "Undergraduate Headcount by Program", x = "Term", y = "Student Count") +
        theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
        scale_fill_brewer(palette = "Set2", name = "Program Type")
    } else {
      p_undergrad <- ggplot(undergrad_data, aes(x = term, y = student_count, fill = program_type)) +
        geom_bar(stat = "identity", position = "stack") +
        facet_wrap(~program_type, scales = "fixed", ncol = 2) +
        labs(title = "Undergraduate Headcount", x = "Term", y = "Student Count") +
        theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
        scale_fill_brewer(palette = "Set2", name = "Program Type")
    }

    plots$undergrad <- ggplotly(p_undergrad) %>%
      layout(legend = list(orientation = 'h', x = 0.3, y = -0.3))
  } else {
    plots$undergrad <- NULL
    message("[headcount.R] No undergraduate data to plot")
  }

  # Graduate plot (CEDAR naming) - use flexible matching for graduate levels
  message("[headcount.R] Creating Graduate plot...")
  grad_data <- summarized[grepl("^Grad", summarized$student_level, ignore.case = TRUE), ]

  if (nrow(grad_data) > 0) {
    if (!has_program_type) {
      # Simple time series when no program_type breakdown
      p_grad <- ggplot(grad_data, aes(x = term, y = student_count)) +
        geom_bar(stat = "identity", fill = "darkgreen") +
        labs(title = "Graduate Headcount", x = "Term", y = "Student Count") +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    } else {
      # Use alpha to distinguish PhD programs if present
      grad_data$alpha_value <- ifelse(grad_data$program_type == "Doctor of Philosophy", 1.0, 0.6)

      if (!no_program && "program_name" %in% colnames(summarized)) {
        p_grad <- ggplot(grad_data, aes(x = term, y = student_count, fill = program_name, alpha = I(alpha_value))) +
          geom_bar(stat = "identity", position = "dodge") +
          labs(title = "Graduate Headcount", x = "Term", y = "Student Count") +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))
      } else {
        p_grad <- ggplot(grad_data, aes(x = term, y = student_count, fill = program_type, alpha = I(alpha_value))) +
          geom_bar(stat = "identity", position = "dodge") +
          labs(title = "Graduate Headcount", x = "Term", y = "Student Count") +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))
      }
    }

    plots$graduate <- ggplotly(p_grad) %>%
      layout(legend = list(orientation = 'h', x = 0.3, y = -.3))
  } else {
    plots$graduate <- NULL
    message("[headcount.R] No graduate data to plot")
  }

  message("[headcount.R] Returning ", length(plots), " plots")
  return(plots)
}


#' Create Single Combined Headcount Plot
#'
#' Creates a single stacked bar chart showing enrollment across all programs and levels.
#'
#' @param summarized Summarized data frame from count_heads_by_program()
#'
#' @return Interactive plotly plot or NULL if no data
#'
#' @details
#' This is a simplified plotting function that creates a single view.
#' For more detailed analysis, use make_headcount_plots_by_level() instead.
#'
#' @export
make_headcount_plot <- function(summarized) {
  message("[headcount.R] Creating combined plot for ", nrow(summarized), " rows...")

  if (nrow(summarized) > 0) {
    # Convert term to factor for discrete x-axis
    summarized$term <- factor(summarized$term, levels = sort(unique(summarized$term)), ordered = TRUE)
    
    message("[headcount.R] Creating ggplot...")
    plot <- summarized %>%
      ggplot(aes(x=term, y=student_count)) +
      theme(legend.position="bottom") +
      guides(color = guide_legend(title = "")) +
      geom_bar(aes(fill=program_type), position="stack", stat="identity") +
      theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))

    message("[headcount.R] Converting to plotly...")
    plot <- ggplotly(plot) %>%
      layout(
        legend = list(orientation = 'h', x = 0.3, y = -.3),
        xaxis = list(standoff = -1)
      )
  } else {
    plot <- NULL
    message("[headcount.R] No data to plot")
  }

  return(plot)
}


#' Count Students by Program (Legacy Function)
#'
#' Legacy headcount function for backward compatibility with older code.
#' Uses mapped DEPT and PRGM codes for filtering.
#'
#' @param academic_studies_data Academic studies data with original column names
#' @param opt Options list with dept, prgm, and term filters
#'
#' @return Data frame with headcount summary
#'
#' @details
#' **DEPRECATED**: This function uses legacy column naming and mapping logic.
#' New code should use count_heads_by_program() with CEDAR-formatted data instead.
#'
#' This function:
#' 1. Pivots programs to long format
#' 2. Maps program names to PRGM and DEPT codes
#' 3. Filters by DEPT or PRGM
#' 4. Summarizes student counts
#'
#' @export
#' Generate Headcount Data and Plots for Department Reports
#'
#' Comprehensive function that generates all headcount data and visualizations
#' needed for department reports. Creates separate plots for undergraduate/graduate
#' and major/minor programs.
#'
#' @param programs Student program enrollment data in CEDAR format.
#'   Required columns: student_id, term, student_level, program_type, program_name.
#'   This is typically the academic_studies dataset with CEDAR naming.
#' @param d_params Department report parameters list with:
#'   \itemize{
#'     \item term_start - Start term for filtering
#'     \item term_end - End term for filtering
#'     \item prog_names - Vector of program names to include
#'     \item tables - Existing tables list (will be updated)
#'     \item plots - Existing plots list (will be updated)
#'   }
#' @param opt Options list for filtering (passed to count_heads_by_program).
#'   Can include filters for campus, college, etc.
#'
#' @return Updated d_params with added tables and plots:
#'   \describe{
#'     \item{tables}{
#'       \itemize{
#'         \item hc_progs_under - All undergrad programs
#'         \item hc_progs_under_long_majors - Undergrad majors only
#'         \item hc_progs_under_long_minors - Undergrad minors only
#'         \item hc_progs_grad - All grad programs
#'         \item hc_progs_grad_long_majors - Grad majors only
#'         \item hc_progs_grad_long_minors - Grad minors only
#'       }
#'     }
#'     \item{plots}{Corresponding plotly plots for each table above}
#'   }
#'
#' @details
#' **CEDAR Data Model Only**
#'
#' This function requires CEDAR-formatted data and will error if legacy column
#' names are provided. There are no fallbacks - CEDAR naming is mandatory.
#'
#' Workflow:
#' 1. Validates CEDAR column structure (errors with clear message if missing)
#' 2. Calls get_headcount() to get aggregated headcount data
#' 3. Filters by term range and program names
#' 4. Splits into undergraduate/graduate and major/minor subsets
#' 5. Creates plotly plots for each subset
#' 6. Returns all data and plots via d_params
#'
#' **Column Mappings (Legacy → CEDAR):**
#' - term_code → term
#' - Student Level → student_level
#' - major_type → program_type
#' - major_name → program_name
#'
#' @export
get_headcount_data_for_dept_report <- function(programs, d_params, opt = list()) {
  message("[headcount.R] Welcome to get_headcount_data_for_dept_report!")

  # Validate CEDAR data structure
  required_cols <- c("student_id", "term", "student_level", "program_type", "program_name")
  missing_cols <- setdiff(required_cols, colnames(programs))
  if (length(missing_cols) > 0) {
    stop("[headcount.R] Missing required CEDAR columns in programs data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Run data transformation scripts to create CEDAR-formatted data.")
  }

  # Build opt for filtering from d_params if opt is empty
  # For dept reports, filter by department to include ALL program types (majors, minors, concentrations)
  # d_params$dept_raw has the raw department value that matches cedar_programs.department
  if (length(opt) == 0 && !is.null(d_params$dept_raw) && d_params$dept_raw != "") {
    opt$dept <- d_params$dept_raw
    message("[headcount.R] Built opt from d_params: filtering by department = ", d_params$dept_raw)
  }

  # DEBUG: Summary of raw data before filtering
  message("[headcount.R] DEBUG - Program types in raw data: ",
          paste(names(table(programs$program_type)), "=", table(programs$program_type), collapse = ", "))

  # Get headcount data using CEDAR function
  message("[headcount.R] Counting heads with CEDAR data model...")
  result <- get_headcount(programs, opt)
  headcount <- result$data

  # DEBUG: Check what came back after filtering
  message("[headcount.R] DEBUG - Program types in filtered headcount data:")
  print(table(headcount$program_type))
  message("[headcount.R] DEBUG - Student levels in filtered headcount data:")
  print(table(headcount$student_level))
  if (nrow(headcount) > 0) {
    message("[headcount.R] DEBUG - Sample filtered headcount by student_level and program_type:")
    sample_summary <- headcount %>%
      group_by(student_level, program_type) %>%
      summarize(total_students = sum(student_count), .groups = "drop")
    print(sample_summary)
  }

  # Filter by term range (CEDAR: term not term_code)
  headcount_filtered <- headcount %>%
    filter(term >= d_params$term_start & term <= d_params$term_end)

  # Define program type groups
  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  # UNDERGRADUATE data splits (CEDAR: student_level not `Student Level`)
  message("[headcount.R] Processing undergraduate data...")
  hc_progs_under <- headcount_filtered %>%
    filter(student_level == "Undergraduate")
  d_params$tables[["hc_progs_under"]] <- hc_progs_under

  hc_progs_under_long_majors <- hc_progs_under %>%
    filter(program_type %in% major_types & student_count > 0)
  d_params$tables[["hc_progs_under_long_majors"]] <- hc_progs_under_long_majors

  hc_progs_under_long_minors <- hc_progs_under %>%
    filter(program_type %in% minor_types & student_count > 0)
  d_params$tables[["hc_progs_under_long_minors"]] <- hc_progs_under_long_minors

  # GRADUATE data splits (CEDAR: student_level not `Student Level`)
  # Use ^Grad to match only strings STARTING with "Grad" (not "Undergraduate" which contains "grad")
  message("[headcount.R] Processing graduate data...")
  grad_levels <- unique(headcount_filtered$student_level[grepl("^Grad", headcount_filtered$student_level, ignore.case = TRUE)])
  message("[headcount.R] Detected graduate levels: ", paste(grad_levels, collapse = ", "))
  hc_progs_grad <- headcount_filtered %>%
    filter(grepl("^Grad", student_level, ignore.case = TRUE))
  d_params$tables[["hc_progs_grad"]] <- hc_progs_grad

  hc_progs_grad_long_majors <- hc_progs_grad %>%
    filter(program_type %in% major_types & student_count > 0)
  d_params$tables[["hc_progs_grad_long_majors"]] <- hc_progs_grad_long_majors

  hc_progs_grad_long_minors <- hc_progs_grad %>%
    filter(program_type %in% minor_types & student_count > 0)
  d_params$tables[["hc_progs_grad_long_minors"]] <- hc_progs_grad_long_minors

  # CREATE PLOTS for each data subset
  message("[headcount.R] Creating plots...")

  plot_names <- c("hc_progs_under_long_majors",
                  "hc_progs_under_long_minors",
                  "hc_progs_grad_long_majors",
                  "hc_progs_grad_long_minors")

  for (data_name in plot_names) {
    data <- d_params$tables[[data_name]]

    if (!is.null(data) && nrow(data) > 0) {
      message("[headcount.R] Creating plot for ", data_name)

      # CEDAR: use term not term_code, program_type not major_type, student_count not students
      plot <- data %>%
        ggplot(aes(x = term, y = student_count)) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_bar(aes(fill = program_type), position = "stack", stat = "identity") +
        theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1))

      plot <- ggplotly(plot) %>%
        layout(
          legend = list(orientation = 'h', x = 0.3, y = -.3),
          xaxis = list(standoff = -1)
        )

      plot_name <- paste0(data_name, "_plot")
      d_params$plots[[plot_name]] <- plot
    } else {
      message("[headcount.R] No data for ", data_name, " - skipping plot")
    }
  }

  message("[headcount.R] Returning d_params with ",
          length(d_params$tables), " tables and ",
          length(d_params$plots), " plots")

  return(d_params)
}
