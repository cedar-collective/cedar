#' Headcount: Student Program Enrollment Analysis
#'
#' Functions for analyzing student enrollment by academic program
#' (majors, minors, concentrations) over time.
#'
#' @section Data Requirements:
#' Requires cedar_programs table with CEDAR column names (lowercase with underscores):
#' - student_id (encrypted student identifier)
#' - term (integer term code, e.g., 202580)
#' - student_campus (campus code, consistent across all program rows for a student per term)
#' - student_college (college code for student's primary college)
#' - student_level ("Undergraduate", "Graduate/GASM")
#' - degree (degree type)
#' - dept_code (department code derived from the program's major code)
#' - program_type ("Major", "Second Major", "First Minor", "Second Minor",
#'                 "First Concentration", "Second Concentration", "Third Concentration")
#' - program_name (program name)
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
#' @examples
#' \dontrun{
#' # Headcount for a department
#' result <- get_headcount(cedar_programs, list(dept = "MATH"))
#'
#' # Students with both a History major and an Anthropology minor
#' result <- get_headcount(cedar_programs, list(major = "History", minor = "Anthropology"))
#'
#' # Custom grouping for SFR calculations
#' result <- get_headcount(
#'   cedar_programs,
#'   opt      = list(),
#'   group_by = c("term", "dept_code", "student_level")
#' )
#'
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
#' **Filtering strategy**
#'
#' Campus and college are row-level filters. Because these attributes are the same
#' across all program rows for a student in a given term, row-level filtering is
#' equivalent to student-level filtering and safe to apply directly.
#'
#' Dept uses an ID-scope approach: students who have ANY program row with a matching
#' dept_code are identified, then ALL of their rows are kept. This preserves minor and
#' concentration rows whose dept_code differs from their major's dept_code.
#'
#' Major, minor, and concentration each independently find the set of student IDs that
#' satisfy that criterion, then intersect them. A student must satisfy every active
#' program filter to be included (AND logic across filters). When multiple program
#' filters are active, only rows for the primary filter are returned (major > minor >
#' concentration), so the plot shows a single series rather than one facet per type.
#'
#' @keywords internal
filter_programs_by_opt <- function(programs, opt = list()) {

  # Select important columns (CEDAR naming)
  important_cols <- c("student_id", "term", "student_college", "student_campus",
                      "student_level", "degree", "dept_code",
                      "program_type", "program_name")

  message("[headcount.R] Selecting CEDAR columns...")
  available_cols <- important_cols[important_cols %in% colnames(programs)]
  df <- programs %>% select(all_of(available_cols)) %>% distinct()
  message("[headcount.R] Data shape: ", nrow(df), " rows, ", ncol(df), " cols")

  # Campus/college: row-level filters (consistent across all program rows for a student)
  if (!is.null(opt$campus) && length(opt$campus) > 0) {
    message("[headcount.R] Filtering by campus: ", paste(opt$campus, collapse = ", "))
    df <- df %>% filter(student_campus %in% opt$campus)
  }

  if (!is.null(opt$college) && length(opt$college) > 0) {
    message("[headcount.R] Filtering by college: ", paste(opt$college, collapse = ", "))
    df <- df %>% filter(student_college %in% opt$college)
  }

  # Dept: scope to students who have ANY program in that dept, then keep ALL their rows.
  # Row-level dept filtering would drop minor/concentration rows from other depts.
  if (!is.null(opt$dept) && length(opt$dept) > 0) {
    message("[headcount.R] Filtering by department: ", paste(opt$dept, collapse = ", "))
    dept_ids <- df %>%
      filter(dept_code %in% opt$dept, !is.na(student_id)) %>%
      distinct(student_id) %>%
      pull(student_id)
    df <- df %>% filter(student_id %in% dept_ids)
  }

  has_program_filter <- FALSE

  # Program filters: find student_ids matching each criterion independently, then
  # intersect so that combined filters (e.g. major + minor) require BOTH.
  # This avoids the sequential-filter bug where major filter removes minor-type rows.
  scoped_ids <- df %>% filter(!is.na(student_id)) %>% distinct(student_id) %>% pull(student_id)

  if (!is.null(opt$major) && length(opt$major) > 0) {
    message("[headcount.R] Filtering by major: ", paste(opt$major, collapse = ", "))
    major_ids <- df %>%
      filter(program_type %in% c("Major", "Second Major"),
             program_name %in% opt$major, !is.na(student_id)) %>%
      distinct(student_id) %>% pull(student_id)
    scoped_ids <- intersect(scoped_ids, major_ids)
    has_program_filter <- TRUE
  }

  if (!is.null(opt$minor) && length(opt$minor) > 0) {
    message("[headcount.R] Filtering by minor: ", paste(opt$minor, collapse = ", "))
    minor_ids <- df %>%
      filter(program_type %in% c("First Minor", "Second Minor"),
             program_name %in% opt$minor, !is.na(student_id)) %>%
      distinct(student_id) %>% pull(student_id)
    scoped_ids <- intersect(scoped_ids, minor_ids)
    has_program_filter <- TRUE
  }

  if (!is.null(opt$concentration) && length(opt$concentration) > 0) {
    message("[headcount.R] Filtering by concentration: ", paste(opt$concentration, collapse = ", "))
    conc_ids <- df %>%
      filter(program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"),
             program_name %in% opt$concentration, !is.na(student_id)) %>%
      distinct(student_id) %>% pull(student_id)
    scoped_ids <- intersect(scoped_ids, conc_ids)
    has_program_filter <- TRUE
  }

  if (has_program_filter) {
    df <- df %>% filter(student_id %in% scoped_ids)

    # When multiple program filters are combined (e.g. major + minor), secondary filters
    # already narrowed scoped_ids above. Now keep only the rows for the PRIMARY filter
    # so the plot shows a single series rather than one facet per program type.
    # Priority: major > minor > concentration.
    if (!is.null(opt$major) && length(opt$major) > 0) {
      df <- df %>% filter(program_type %in% c("Major", "Second Major"),
                          program_name %in% opt$major)
    } else if (!is.null(opt$minor) && length(opt$minor) > 0) {
      df <- df %>% filter(program_type %in% c("First Minor", "Second Minor"),
                          program_name %in% opt$minor)
    } else if (!is.null(opt$concentration) && length(opt$concentration) > 0) {
      df <- df %>% filter(
        program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"),
        program_name %in% opt$concentration)
    }
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
#' @param group_by Character vector of column names to group by. When NULL:
#'   - No program filter: groups by c("term", "student_level", "program_type")
#'   - Program filter active: groups by c("term", "student_level", "program_type", "program_name")
#'   Pass explicitly for custom aggregations (e.g. SFR: c("term", "dept_code", "student_level")).
#'
#' @return Data frame with columns from group_by plus student_count (distinct student IDs)
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

  # Filter out empty program names and summarize
  summarized <- df %>%
    filter(!is.na(program_name) & program_name != "") %>%
    group_by(across(all_of(group_by))) %>%
    summarize(student_count = n_distinct(student_id), .groups = "drop") %>%
    arrange(across(all_of(group_by)))

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
#' Main orchestrating function for calculating student headcount from CEDAR programs data.
#'
#' @param programs Student program enrollment data in CEDAR format.
#'   Required columns: student_id, term, student_level, program_type, program_name, dept_code.
#'   Optional columns: student_college, student_campus, degree.
#' @param opt Options list for filtering:
#'   \itemize{
#'     \item campus - Filter by campus code(s)
#'     \item college - Filter by college code(s)
#'     \item dept - Filter by department code(s); scopes to students with any program in
#'           that dept, preserving their minor/concentration rows from other depts
#'     \item major - Filter by major program name(s)
#'     \item minor - Filter by minor program name(s)
#'     \item concentration - Filter by concentration name(s)
#'   }
#'   Multiple program filters (major + minor, etc.) are combined with AND logic:
#'   only students satisfying all specified filters are counted. The plot reflects
#'   the primary filter (major > minor > concentration).
#' @param group_by Optional character vector of columns to group by.
#'   Defaults to c("term", "student_level", "program_type", "program_name") when a
#'   program filter is active, or c("term", "student_level", "program_type") otherwise.
#'   Pass explicitly for custom aggregations (e.g. SFR: c("term", "dept_code", "student_level")).
#'
#' @return List with:
#'   \describe{
#'     \item{data}{Data frame with student_count and grouping columns}
#'     \item{no_program_filter}{TRUE when no major/minor/concentration filter was applied}
#'     \item{metadata}{List with total_students, programs_included, filters_applied}
#'   }
#'
#' @details
#' Delegates to \code{\link{filter_programs_by_opt}}, \code{\link{summarize_headcount}},
#' and \code{\link{format_headcount_result}}. See \code{\link{filter_programs_by_opt}}
#' for details on the ID-scope filtering strategy.
#'
#' @examples
#' \dontrun{
#' # All programs in a department
#' result <- get_headcount(cedar_programs, list(dept = "HIST"))
#'
#' # History majors who also have an Anthropology minor
#' result <- get_headcount(cedar_programs, list(major = "History", minor = "Anthropology"))
#'
#' # SFR aggregation
#' result <- get_headcount(
#'   cedar_programs,
#'   opt      = list(),
#'   group_by = c("term", "dept_code", "student_level")
#' )
#' }
#'
#' @seealso \code{\link{filter_programs_by_opt}}, \code{\link{make_headcount_plots_by_level}}
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
  undergrad_data$term <- as.factor(undergrad_data$term)

  if (nrow(undergrad_data) > 0) {
    if (!has_program_type) {
      plots$undergrad <- plot_ly(undergrad_data, x = ~term, y = ~student_count,
                                 type = "bar", marker = list(color = "steelblue"),
                                 hovertemplate = "%{x}<br>Students: %{y}<extra></extra>") %>%
        layout(title = list(text = "Undergraduate Headcount", x = 0),
               xaxis = list(title = "Term", tickangle = -45),
               yaxis = list(title = "Student Count"))
    } else if (!no_program && "program_name" %in% colnames(summarized)) {
      prog_names <- unique(undergrad_data$program_name)
      sub_plots  <- lapply(seq_along(prog_names), function(i) {
        pn <- prog_names[[i]]
        plot_ly(undergrad_data %>% filter(program_name == pn),
                x = ~term, y = ~student_count, color = ~program_type,
                colors = "Set2", type = "bar",
                showlegend  = (i == 1), legendgroup = ~program_type,
                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
          layout(barmode = "stack",
                 annotations = list(list(text = pn, showarrow = FALSE,
                                         xref = "paper", yref = "paper",
                                         x = 0.5, y = 1.05, font = list(size = 11))),
                 xaxis = list(tickangle = -45))
      })
      plots$undergrad <- subplot(sub_plots, nrows = ceiling(length(prog_names) / 2),
                                 shareX = FALSE, shareY = FALSE,
                                 titleX = TRUE, titleY = TRUE, margin = 0.08) %>%
        layout(title  = list(text = "Undergraduate Headcount by Program", x = 0),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.15))
    } else {
      prog_types <- unique(undergrad_data$program_type)
      sub_plots  <- lapply(seq_along(prog_types), function(i) {
        pt <- prog_types[[i]]
        plot_ly(undergrad_data %>% filter(program_type == pt),
                x = ~term, y = ~student_count, color = ~program_type,
                colors = "Set2", type = "bar",
                showlegend  = (i == 1), legendgroup = ~program_type,
                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
          layout(barmode = "stack",
                 annotations = list(list(text = pt, showarrow = FALSE,
                                         xref = "paper", yref = "paper",
                                         x = 0.5, y = 1.05, font = list(size = 11))),
                 xaxis = list(tickangle = -45))
      })
      plots$undergrad <- subplot(sub_plots, nrows = ceiling(length(prog_types) / 2),
                                 shareX = FALSE, shareY = FALSE,
                                 titleX = TRUE, titleY = TRUE, margin = 0.08) %>%
        layout(title  = list(text = "Undergraduate Headcount", x = 0),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.15))
    }
  } else {
    plots$undergrad <- NULL
    message("[headcount.R] No undergraduate data to plot")
  }

  # Graduate plot (CEDAR naming) - use flexible matching for graduate levels
  message("[headcount.R] Creating Graduate plot...")
  grad_data <- summarized[grepl("^Grad", summarized$student_level, ignore.case = TRUE), ]
  grad_data$term <- as.factor(grad_data$term)

  if (nrow(grad_data) > 0) {
    if (!has_program_type) {
      plots$graduate <- plot_ly(grad_data, x = ~term, y = ~student_count,
                                type = "bar", marker = list(color = "darkgreen"),
                                hovertemplate = "%{x}<br>Students: %{y}<extra></extra>") %>%
        layout(title = list(text = "Graduate Headcount", x = 0),
               xaxis = list(title = "Term", tickangle = -45),
               yaxis = list(title = "Student Count"))
    } else {
      fill_col <- if (!no_program && "program_name" %in% colnames(summarized)) ~program_name else ~program_type
      plots$graduate <- plot_ly(grad_data, x = ~term, y = ~student_count, color = fill_col,
                                type = "bar",
                                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(barmode = "group",
               title  = list(text = "Graduate Headcount", x = 0),
               xaxis  = list(title = "Term", tickangle = -45),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.2))
    }
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
    summarized$term <- as.character(sort(unique(summarized$term)))[
      match(summarized$term, sort(unique(summarized$term)))]

    message("[headcount.R] Creating plotly chart...")
    plot <- plot_ly(summarized, x = ~term, y = ~student_count, color = ~program_type,
                   type          = "bar",
                   hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
      layout(barmode = "stack",
             xaxis   = list(tickangle = -45),
             legend  = list(orientation = "h", x = 0, y = -0.2))
  } else {
    plot <- NULL
    message("[headcount.R] No data to plot")
  }

  return(plot)
}


#' Headcount Sparkline for Department Dashboard
#'
#' Creates a compact static ggplot showing term-by-term headcount for a
#' department's major and minor programs. Faceted by student level
#' (Undergraduate / Graduate), with separate lines for Majors and Minors.
#' Summer terms are already excluded by \code{get_headcount_series()}.
#' Intended for embedding in the "Explore Your Unit" dashboard summary.
#'
#' @param series Data frame returned by \code{get_headcount_series()} in
#'   dept-dashboard.R. Columns: term, group, student_level_clean, program_cat, count.
#' @return A ggplot object, or NULL if series is NULL/empty.
#' @export
make_headcount_sparklines <- function(series) {
  message("[headcount.R] make_headcount_sparklines")

  if (is.null(series) || nrow(series) == 0) return(NULL)

  # Keep only levels that have data so we don't show empty facets
  levels_present <- unique(series$student_level_clean)
  if (length(levels_present) == 0) return(NULL)

  series <- series %>%
    dplyr::mutate(
      student_level_clean = factor(student_level_clean,
                                   levels = c("Undergraduate", "Graduate")),
      program_cat = factor(program_cat, levels = c("Majors", "Minors"))
    )

  # Term labels: use last 2 digits of year + season initial for compactness
  # e.g. 202380 → "Fa23", 202410 → "Sp24"
  make_term_label <- function(term_code) {
    yr <- floor(term_code / 100) %% 100
    tt <- term_code %% 100
    season <- dplyr::case_when(tt == 10 ~ "Sp", tt == 80 ~ "Fa", TRUE ~ "Su")
    paste0(season, sprintf("%02d", yr))
  }

  # Build ordered factor from sorted unique terms
  all_terms <- sort(unique(series$term))
  term_labels <- sapply(all_terms, make_term_label)

  series <- series %>%
    dplyr::mutate(term_label = factor(make_term_label(term),
                                      levels = term_labels, ordered = TRUE))

  ggplot2::ggplot(series, ggplot2::aes(
    x     = term_label,
    y     = count,
    color = program_cat,
    group = program_cat
  )) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::facet_wrap(~ student_level_clean,
                        scales = "free_y",
                        ncol   = length(levels_present)) +
    ggplot2::scale_color_manual(
      values = c(Majors = "#e07b00", Minors = "#1565c0"),
      labels = c(Majors = "Majors (incl. 2nd)", Minors = "Minors"),
      name   = NULL
    ) +
    ggplot2::scale_y_continuous(labels = scales::comma_format(accuracy = 1)) +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.x      = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      axis.text.y      = ggplot2::element_text(size = 8),
      legend.position  = "top",
      legend.text      = ggplot2::element_text(size = 9),
      panel.grid.minor = ggplot2::element_blank(),
      strip.text       = ggplot2::element_text(size = 10, face = "bold")
    )
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
#' @param dept_code Character. Department code for filtering (e.g., "HIST", "MATH").
#' @param term_start Integer. Starting term code for filtering (e.g., 201980).
#' @param term_end Integer. Ending term code for filtering (e.g., 202580).
#' @param opt Options list for filtering (passed to get_headcount).
#'   Can include filters for campus, college, etc. If empty, dept_code is used.
#'
#' @return List with structure:
#'   list(
#'     plots  = list(hc_progs_under_long_majors_plot, hc_progs_under_long_minors_plot,
#'                   hc_progs_grad_long_majors_plot,   hc_progs_grad_long_minors_plot),
#'     tables = list(hc_progs_under, hc_progs_under_long_majors, hc_progs_under_long_minors,
#'                   hc_progs_grad,  hc_progs_grad_long_majors,  hc_progs_grad_long_minors)
#'   )
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
#' 3. Filters by term range
#' 4. Splits into undergraduate/graduate and major/minor subsets
#' 5. Creates plotly plots for each subset
#' 6. Returns plots and tables as a plain list
#'
#' **Column Mappings (Legacy → CEDAR):**
#' - term_code → term
#' - Student Level → student_level
#' - major_type → program_type
#' - major_name → program_name
#'
#' @export
get_headcount_data_for_dept_report <- function(programs, dept_code, term_start, term_end, opt = list()) {
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

  if (length(opt) == 0) {
    opt$dept <- dept_code
    message("[headcount.R] filtering by dept_code = ", dept_code)
  }

  # Get headcount data using CEDAR function
  message("[headcount.R] Counting heads with CEDAR data model...")
  result <- get_headcount(programs, opt)
  headcount <- result$data


  # Filter by term range (CEDAR: term not term_code)
  headcount_filtered <- headcount %>%
    filter(term >= term_start & term <= term_end)

  # Define program type groups
  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  tables <- list()
  plots  <- list()

  # UNDERGRADUATE data splits (CEDAR: student_level not `Student Level`)
  message("[headcount.R] Processing undergraduate data...")
  hc_progs_under <- headcount_filtered %>%
    filter(student_level == "Undergraduate")
  tables[["hc_progs_under"]] <- hc_progs_under

  hc_progs_under_long_majors <- hc_progs_under %>%
    filter(program_type %in% major_types & student_count > 0)
  tables[["hc_progs_under_long_majors"]] <- hc_progs_under_long_majors

  hc_progs_under_long_minors <- hc_progs_under %>%
    filter(program_type %in% minor_types & student_count > 0)
  tables[["hc_progs_under_long_minors"]] <- hc_progs_under_long_minors

  # GRADUATE data splits (CEDAR: student_level not `Student Level`)
  # Use ^Grad to match only strings STARTING with "Grad" (not "Undergraduate" which contains "grad")
  message("[headcount.R] Processing graduate data...")
  grad_levels <- unique(headcount_filtered$student_level[grepl("^Grad", headcount_filtered$student_level, ignore.case = TRUE)])
  message("[headcount.R] Detected graduate levels: ", paste(grad_levels, collapse = ", "))
  hc_progs_grad <- headcount_filtered %>%
    filter(grepl("^Grad", student_level, ignore.case = TRUE))
  tables[["hc_progs_grad"]] <- hc_progs_grad

  hc_progs_grad_long_majors <- hc_progs_grad %>%
    filter(program_type %in% major_types & student_count > 0)
  tables[["hc_progs_grad_long_majors"]] <- hc_progs_grad_long_majors

  hc_progs_grad_long_minors <- hc_progs_grad %>%
    filter(program_type %in% minor_types & student_count > 0)
  tables[["hc_progs_grad_long_minors"]] <- hc_progs_grad_long_minors

  # CREATE PLOTS for each data subset
  message("[headcount.R] Creating plots...")

  plot_names <- c("hc_progs_under_long_majors",
                  "hc_progs_under_long_minors",
                  "hc_progs_grad_long_majors",
                  "hc_progs_grad_long_minors")

  for (data_name in plot_names) {
    data <- tables[[data_name]]

    if (!is.null(data) && nrow(data) > 0) {
      message("[headcount.R] Creating plot for ", data_name)

      # Convert term to factor for discrete x-axis labels
      data$term <- as.factor(data$term)

      # CEDAR: use term not term_code, program_type not major_type, student_count not students
      plot <- plot_ly(data, x = ~term, y = ~student_count, color = ~program_type,
                      type          = "bar",
                      hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(barmode = "stack",
               xaxis   = list(tickangle = -45),
               legend  = list(orientation = "h", x = 0, y = -0.2))

      plots[[paste0(data_name, "_plot")]] <- plot
    } else {
      message("[headcount.R] No data for ", data_name, " - skipping plot")
    }
  }

  message("[headcount.R] Returning ", length(tables), " tables and ", length(plots), " plots")
  list(plots = plots, tables = tables)
}
