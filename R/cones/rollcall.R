# rollcall.R provides data on the major and classification of students in a course or set of courses
# no params required, but then too much data is outputted
# best to specify at least a course (or course_list) to see change over time, and/or a term


#' Abbreviate Student Classification Labels
#'
#' Converts verbose MyReports classification labels to shorter display labels
#' to prevent layout issues in pie charts and legends.
#'
#' @param classification Character vector of student classification values
#' @return Character vector with abbreviated labels
#' @examples
#' abbreviate_classification("Freshman, 1st Yr, 1st Sem")  # Returns "Freshman"
#' abbreviate_classification("Junior, 3rd Yr.")  # Returns "Junior"
abbreviate_classification <- function(classification) {
  # Mapping from verbose MyReports values to short display labels
  # Pattern: extract just the main classification (Freshman, Sophomore, Junior, Senior)
  # Handle both verbose and simple formats
  abbreviations <- c(
    # Verbose formats from MyReports
    "Freshman, 1st Yr, 1st Sem" = "Freshman",
    "Freshman, 1st Yr, 2nd Sem" = "Freshman",
    "Freshman, 1st Yr." = "Freshman",
    "Sophomore, 2nd Yr, 1st Sem" = "Sophomore",
    "Sophomore, 2nd Yr, 2nd Sem" = "Sophomore",
    "Sophomore, 2nd Yr." = "Sophomore",
    "Junior, 3rd Yr, 1st Sem" = "Junior",
    "Junior, 3rd Yr, 2nd Sem" = "Junior",
    "Junior, 3rd Yr." = "Junior",
    "Senior, 4th Yr, 1st Sem" = "Senior",
    "Senior, 4th Yr, 2nd Sem" = "Senior",
    "Senior, 4th Yr." = "Senior",
    "Senior, 5th Yr. and Beyond" = "Senior 5+",
    # Graduate levels
    "Graduate, Masters" = "Masters",
    "Graduate, Doctoral" = "Doctoral",
    "Graduate" = "Graduate",
    # Simple formats (already short)
    "Freshman" = "Freshman",
    "Sophomore" = "Sophomore",
    "Junior" = "Junior",
    "Senior" = "Senior"
  )

  # Apply mapping; if not found, try to extract first word before comma
  result <- ifelse(
    classification %in% names(abbreviations),
    abbreviations[classification],
    # Fallback: extract first word before comma or return as-is
    gsub(",.*$", "", classification)
  )

  return(result)
}


#' Summarize Student Demographics
#'
#' Flexible demographic summary function that groups students by any specified columns
#' (majors, classifications, or other demographic fields) and calculates enrollment
#' counts, means across terms, and percentages of course enrollment. This provides
#' insight into "who" is taking courses over time.
#'
#' @param filtered_students Data frame of student enrollments from cedar_students table,
#'   already filtered by desired criteria. Must include: student_id, term, campus,
#'   college, subject_course, and any demographic columns used in grouping.
#' @param opt Options list containing:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of column names to group by.
#'       If NULL, uses default: campus, college, term, term_type, major,
#'       student_classification, subject_course, course_title, level
#'   }
#'
#' @return Data frame with student demographic breakdown including:
#'   \describe{
#'     \item{count}{Number of distinct students in this group for THIS SPECIFIC TERM}
#'     \item{mean}{Average count across all terms OF THE SAME TERM_TYPE (e.g., avg across all falls).
#'       This is the key value used for plotting "average students per term type".}
#'     \item{registered}{Total course enrollment for this specific term}
#'     \item{registered_mean}{Average course enrollment across terms of same term_type}
#'     \item{term_pct}{Percentage of course enrollment this group represents IN THIS TERM
#'       (count / registered * 100)}
#'     \item{term_type_pct}{AVERAGE percentage across all terms of this term_type
#'       (mean / registered_mean * 100). This is what the pie charts display.}
#'   }
#'   Plus all columns specified in group_cols.
#'
#' @section Key Concept - Term Type Averaging:
#' The \code{mean} and \code{term_type_pct} columns answer: "On average, what percentage
#' of students in HIST 1105 are freshmen in fall semesters?" This averages across
#' Fall 2022, Fall 2023, Fall 2024, etc. to give a stable "typical" value.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Groups students by specified columns and counts distinct student_ids
#'   \item Removes term from grouping and calculates mean counts across terms
#'   \item Calls \code{calc_cl_enrls()} to get total course enrollment counts
#'   \item Merges demographic counts with enrollment totals
#'   \item Calculates percentages: what % of course enrollment does each group represent
#'   \item Sorts by campus, college, term, course, and descending percentage
#' }
#'
#' This function is useful for answering questions like:
#' \itemize{
#'   \item "What majors are taking MATH 1430?"
#'   \item "Are freshmen or seniors more represented in this course?"
#'   \item "How has the major composition of BIOL 1110 changed over time?"
#'   \item "What percentage of course enrollment comes from each college?"
#' }
#'
#' @examples
#' \dontrun{
#' # Summarize by major
#' opt <- list(
#'   course = "MATH 1430",
#'   group_cols = c("campus", "college", "term", "major", "subject_course")
#' )
#' filtered <- filter_class_list(cedar_students, opt)
#' major_summary <- summarize_student_demographics(filtered, opt)
#'
#' # Summarize by classification
#' opt$group_cols <- c("campus", "term", "student_classification", "subject_course")
#' class_summary <- summarize_student_demographics(filtered, opt)
#' }
#'
#' @seealso
#' \code{\link{rollcall}} for complete rollcall analysis,
#' \code{\link{calc_cl_enrls}} for enrollment counts
#'
#' @export
summarize_student_demographics <- function(filtered_students, opt) {
  message("[rollcall.R] Welcome to summarize_student_demographics!")

  group_cols <- opt[["group_cols"]]

  # Set default group_cols if not provided
  if (is.null(group_cols)) {
    message("[rollcall.R] No group_cols specified. Using defaults.")
    group_cols <- c("campus", "college", "term", "term_type",
                    "major", "student_classification", "subject_course", "course_title", "level")
  } else {
    message("[rollcall.R] Using provided group_cols.")
    group_cols <- convert_param_to_list(group_cols)
    group_cols <- as.character(group_cols)
  }

  message("[rollcall.R] group_cols: ", paste(group_cols, collapse = ", "))

  # Group and count distinct students
  summary <- filtered_students %>%
    group_by_at(group_cols) %>%
    distinct(student_id, .keep_all = TRUE) %>%
    summarize(.groups = "keep", count = n())

  # Regroup without "term" to calculate means across terms
  group_cols <- group_cols[-which(group_cols %in% c("term"))]

  # Calculate mean of counts of students by group_cols across all terms
  summary <- summary %>%
    group_by_at(group_cols) %>%
    mutate(mean = round(mean(count), digits = 1))

  # Count course enrollments and percentages
  reg_summary <- calc_cl_enrls(filtered_students)

  # Ungroup for merging and select relevant columns
  crse_enrollment <- reg_summary %>%
    ungroup() %>%
    select(c(campus, college, subject_course, term, registered, registered_mean))

  # Merge summary of demographics with course enrollment data
  merge_sum_enrl <- merge(summary, crse_enrollment, by = c("campus", "college",
                                                           "term", "subject_course"))
  # Regroup and calculate percentages
  merge_sum_enrl <- merge_sum_enrl %>%
    group_by(campus, college, term, subject_course) %>%
    mutate(term_pct = round(count / registered * 100, digits = 1)) %>%
    mutate(term_type_pct = round(mean / registered_mean  * 100, digits = 1)) %>%
    arrange(campus, college, term, subject_course, desc(term_pct))


  message("[rollcall.R] Returning student demographic summary with ", nrow(merge_sum_enrl), " rows...")
  return(merge_sum_enrl)
}

#' @describeIn summarize_student_demographics Deprecated name for backward compatibility
#' @export
summarize_classifications <- function(filtered_students, opt) {
  warning("[rollcall.R] summarize_classifications() is deprecated. Use summarize_student_demographics() instead.")
  summarize_student_demographics(filtered_students, opt)
}


#' Create Consistent Color Palette for Rollcall Plots
#'
#' Generates a consistent color mapping for categories across multiple plots to ensure
#' the same majors/classifications have the same colors in fall, spring, and summer plots.
#' @param rollcall_data A dataframe containing rollcall data across all term types.
#' @param fill_column The column name to use for color mapping (e.g., "Student Classification" or "Major")
#' @param top_n Number of top categories to include in color palette (default: 10)
#' @return A named vector of colors where names are category values
#' @examples
#' color_palette <- create_rollcall_color_palette(rollcall_data, "Major", top_n = 8)
create_rollcall_color_palette <- function(rollcall_data, fill_column, top_n = 10) {
  message("[rollcall.R] Creating consistent color palette for ", fill_column)

  # Make a working copy to avoid modifying original data
  working_data <- rollcall_data

  # Abbreviate classification labels if this is the classification column
  if (fill_column == "student_classification" && "student_classification" %in% colnames(working_data)) {
    working_data <- working_data %>%
      mutate(student_classification = abbreviate_classification(student_classification))
    message("[rollcall.R] Abbreviated classification labels for color palette")
  }

  # For consistent colors across terms, we need to include ALL categories that might
  # appear in any term's top-n display, not just the overall top-n.
  # Strategy: Get top categories from each term_type, then create palette for the union.

  if ("term_type" %in% colnames(working_data)) {
    # Get top categories for each term_type
    top_by_term <- working_data %>%
      group_by(term_type, !!sym(fill_column)) %>%
      summarise(term_pct = sum(term_type_pct, na.rm = TRUE), .groups = "drop") %>%
      group_by(term_type) %>%
      slice_max(order_by = term_pct, n = top_n, with_ties = FALSE) %>%
      ungroup()

    # Get all categories that appear in any term's top-n
    all_categories <- top_by_term %>%
      group_by(!!sym(fill_column)) %>%
      summarise(total_pct = sum(term_pct, na.rm = TRUE), .groups = "drop") %>%
      arrange(desc(total_pct)) %>%
      pull(!!sym(fill_column))
  } else {
    # Fallback: just use overall top-n
    all_categories <- working_data %>%
      group_by(!!sym(fill_column)) %>%
      summarise(total_pct = sum(term_type_pct, na.rm = TRUE), .groups = "drop") %>%
      arrange(desc(total_pct)) %>%
      slice_head(n = top_n) %>%
      pull(!!sym(fill_column))
  }

  # Create color palette using CEDAR-friendly colors
  # Use a colorblind-friendly palette with enough distinct colors
  cedar_colors <- c(
    "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
    "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
    "#aec7e8", "#ffbb78", "#98df8a", "#ff9896", "#c5b0d5"
  )

  # Ensure we have enough colors
  if (length(all_categories) > length(cedar_colors)) {
    # Extend palette by cycling colors with slight variation
    extra_needed <- length(all_categories) - length(cedar_colors)
    cedar_colors <- c(cedar_colors, rep(cedar_colors, ceiling(extra_needed / length(cedar_colors)))[1:extra_needed])
  }

  # Create named vector mapping categories to colors
  color_mapping <- setNames(cedar_colors[1:length(all_categories)], all_categories)

  message("[rollcall.R] Created color palette for ", length(all_categories), " categories: ", paste(all_categories, collapse = ", "))
  return(color_mapping)
}

#' Plot Rollcall Summary with Consistent Colors (Donut Charts)
#'
#' Creates interactive donut charts showing the average distribution of student
#' classifications or majors for a course, grouped by term type (fall, spring, summer).
#'
#' @section Important - Plotting Only:
#' This function does NOT perform calculations. It expects pre-calculated values
#' from \code{\link{summarize_student_demographics}}:
#' \itemize{
#'   \item \code{mean} - Average student count for each category across terms of same term_type
#'   \item \code{term_type_pct} - Percentage based on average total enrollment for term_type
#' }
#'
#' @section Display Format:
#' Each slice shows: "XX% (NN avg)" where:
#' \itemize{
#'   \item XX% = average percentage of course enrollment for this category
#'   \item NN avg = average number of students with this classification/major
#' }
#' Only the top 5 categories by average student count are displayed, but percentages

#' are calculated against total average enrollment (not just top 5).
#'
#' @param rollcall_data Data frame from \code{summarize_student_demographics()}.
#'   Must contain columns: fill_column, term_type, mean, term_type_pct, campus, college, subject_course
#' @param fill_column Column name to group by (e.g., "student_classification" or "major")
#' @param color_palette Named vector of colors from \code{create_rollcall_color_palette()}
#' @param filter_column Optional list with \code{column} and \code{values} for filtering
#'   (e.g., \code{list(column = "campus", values = c("ABQ"))})
#'
#' @return Named list of plotly donut charts:
#' \itemize{
#'   \item \code{fall} - Chart for fall terms (NULL if no data)
#'   \item \code{spring} - Chart for spring terms (NULL if no data)
#'   \item \code{summer} - Chart for summer terms (NULL if no data)
#'   \item \code{by_term} - List of all charts keyed by term_type
#' }
#'
#' @examples
#' \dontrun{
#' # Get rollcall data with pre-calculated averages
#' rollcall_data <- summarize_student_demographics(filtered_students, opt)
#'
#' # Create consistent color palette
#' color_palette <- create_rollcall_color_palette(rollcall_data, "major")
#'
#' # Generate plots
#' plots <- plot_rollcall_summary(rollcall_data, "major", color_palette)
#' plots$fall   # Fall term chart
#' plots$spring # Spring term chart
#' }
#'
#' @seealso
#' \code{\link{summarize_student_demographics}} for data preparation,
#' \code{\link{create_rollcall_color_palette}} for consistent colors,
#' \code{\link{plot_rollcall_with_consistent_colors}} for the wrapper function
plot_rollcall_summary <- function(rollcall_data, fill_column = "student_classification", color_palette = NULL, filter_column = NULL) {
  message("[rollcall.R] Creating circular plot for rollcall summary using fill column: ", fill_column)
  
  # Apply filter if provided
  if (!is.null(filter_column) && !is.null(filter_column$column) && !is.null(filter_column$values)) {
    filter_col <- filter_column$column
    filter_vals <- filter_column$values
    
    if (filter_col %in% colnames(rollcall_data) && length(filter_vals) > 0) {
      original_rows <- nrow(rollcall_data)
      rollcall_data <- rollcall_data %>% filter(!!sym(filter_col) %in% filter_vals)
      message("[rollcall.R] Applied filter on '", filter_col, "' for values: ", paste(filter_vals, collapse = ", "))
      message("[rollcall.R] Filtered data from ", original_rows, " to ", nrow(rollcall_data), " rows")
    } else {
      message("[rollcall.R] Warning: Filter column '", filter_col, "' not found or no filter values provided")
    }
  }
  
  # for testing
  # rollcall_data <- merge_sum_enrl
  # fill_column <- "Major"
  # color_palette <- NULL
  
  # Debug: Check data structure
  message("[rollcall.R] Input data has ", nrow(rollcall_data), " rows and ", ncol(rollcall_data), " columns")
  message("[rollcall.R] Available columns: ", paste(colnames(rollcall_data), collapse = ", "))
  
  # Check if the specified column exists in the data
  if (!fill_column %in% colnames(rollcall_data)) {
    message("[rollcall.R] Warning: Column '", fill_column, "' not found in data. Available columns: ", paste(colnames(rollcall_data), collapse = ", "))
    return(NULL)
  } else {
    message("[rollcall.R] Found specified fill column: ", fill_column)
  }
  
  # Check if pct column exists and has valid data
  if (!"term_type_pct" %in% colnames(rollcall_data)) {
    message("[rollcall.R] Warning: 'term_type_pct' column not found in data")
    return(NULL)
  }
  
  message("[rollcall.R] pct column summary: min=", min(rollcall_data$term_type_pct, na.rm = TRUE),
          ", max=", max(rollcall_data$term_type_pct, na.rm = TRUE),
          ", NAs=", sum(is.na(rollcall_data$term_type_pct)))

  # Abbreviate classification labels if this is the classification column
  if (fill_column == "student_classification" && "student_classification" %in% colnames(rollcall_data)) {
    rollcall_data <- rollcall_data %>%
      mutate(student_classification = abbreviate_classification(student_classification))
    message("[rollcall.R] Abbreviated classification labels for display")
  }

  # =============================================================================
  # PLOTTING ONLY - No calculations here!
  # Uses pre-calculated values from summarize_student_demographics():
  #   - mean: average student count for this category across terms of this term_type
  #   - term_type_pct: percentage based on average total enrollment for term_type
  # =============================================================================

  message("[rollcall.R] Preparing data for plotting (using pre-calculated averages)...")

  # Use pre-calculated mean and term_type_pct - aggregate to one row per category per term_type
  # Since mean and term_type_pct are already averages, we take distinct values
  rollcall_data_for_plot <- rollcall_data %>%
    ungroup() %>%
    select(all_of(c(fill_column, "campus", "college", "subject_course", "term_type", "mean", "term_type_pct"))) %>%
    distinct() %>%
    # Rename for clarity: these are averages per term_type
    rename(avg_students = mean, avg_pct = term_type_pct) %>%
    arrange(campus, college, subject_course, term_type, desc(avg_pct))

  # Create separate plots for each term_type
  term_types <- unique(rollcall_data_for_plot$term_type)
  message("[rollcall.R] Found ", length(term_types), " term types: ", paste(term_types, collapse = ", "))

  plots_by_term <- list()

  for (tt in term_types) {

    message("[rollcall.R] Creating plot for ", tt)

    # Get ALL categories for this term_type (needed for correct percentage base)
    all_term_data <- rollcall_data_for_plot %>%
      filter(term_type == tt)

    if (nrow(all_term_data) == 0) {
      message("[rollcall.R] No data for ", tt)
      next
    }

    # Select top 5 by average student count for display
    term_data <- all_term_data %>%
      slice_max(order_by = avg_students, n = 5, with_ties = FALSE)

    # Create display text using pre-calculated values
    # Format: "XX% (NN students)" where both are averages for this term_type
    term_data <- term_data %>%
      mutate(
        # Round avg_students for display
        display_students = round(avg_students, 0),
        custom_text = paste0(avg_pct, "%\n(", display_students, " avg)")
      )
    
    # Apply consistent colors if palette provided (CEDAR pattern)
    plot_colors <- NULL
    if (!is.null(color_palette)) {
      category_values <- term_data[[fill_column]]
      plot_colors <- color_palette[category_values]

      # Handle any categories not in the palette - assign gray as fallback
      missing_mask <- is.na(plot_colors)
      if (any(missing_mask)) {
        message("[rollcall.R] Warning: ", sum(missing_mask), " categories not in palette, assigning fallback color")
        plot_colors[missing_mask] <- "#999999"  # Gray for unmapped categories
      }

      # Ensure colors are unnamed vector for plotly
      plot_colors <- unname(plot_colors)
      message("[rollcall.R] Applied custom colors for ", length(plot_colors), " categories in ", tt)
    }
    
    # Count how many categories exist (for annotation)
    total_categories <- nrow(all_term_data)
    showing_top_n <- min(5, total_categories)

    term_plot_interactive <- plot_ly(
      data = term_data,
      labels = ~get(fill_column),
      values = ~avg_students,  # Use average student count for proportional sizing
      type = "pie",
      hole = 0.4,  # Creates the donut hole
      text = ~custom_text,
      textinfo = "label+text",  # Show label and our custom percentage + count text
      hovertemplate = paste0("<b>%{label}</b><br>",
                            "Avg Students: %{value:.0f}<br>",
                            "Avg Percentage: %{customdata}%<br>",
                            "<extra></extra>"),
      customdata = ~avg_pct,  # Pass pre-calculated average percentage to hover
      marker = list(
        line = list(color = "white", width = 2),
        colors = plot_colors  # Apply consistent colors
      )
    ) %>%
      layout(
        title = list(
          text = paste0(tools::toTitleCase(tt), " Terms - ", fill_column,
                       "<br><sup>Top ", showing_top_n, " of ", total_categories,
                       " shown; % based on avg total enrollment</sup>"),
          font = list(size = 14)
        ),
        showlegend = TRUE,
        legend = list(orientation = "v", x = 1.1, y = 0.5)
      )
    
    # Store plot with term_type as key (lowercase for consistency)
    plots_by_term[[tolower(tt)]] <- term_plot_interactive
  }
  
  message("[rollcall.R] Created ", length(plots_by_term), " separate plots")
  
  # Return plots organized by term_type
  message("[rollcall.R] Returning ring chart(s).")
  
  # set return list
  return_list <- list(
    fall = plots_by_term[["fall"]],
    spring = plots_by_term[["spring"]],
    summer = plots_by_term[["summer"]],
    by_term = plots_by_term  # All plots in a list
  )

# return_list[["fall"]]
# return_list[["spring"]]

  return(return_list)
}


#' Rollcall: Student Demographics Over Time
#'
#' Main rollcall function that analyzes student demographics (majors, classifications, etc.)
#' in courses over time. Filters students by specified criteria, removes historical data
#' before Fall 2019, and creates demographic summaries with enrollment percentages.
#'
#' @param students Data frame of student enrollments from cedar_students table.
#'   Must include: student_id, term, campus, college, subject_course, registration_status_code,
#'   and any demographic columns for grouping.
#' @param opt Options list for filtering and grouping:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of columns to group by. If NULL, uses defaults:
#'       campus, college, term, term_type, student_classification, major, subject_course,
#'       course_title, level
#'     \item \code{reg_status_code} - Registration status codes to include (default: c("RE", "RS"))
#'     \item \code{term} - Term code(s) to filter by
#'     \item \code{course} - Course identifier(s) to filter by
#'     \item Other filtering options supported by \code{filter_class_list()}
#'   }
#'
#' @return Data frame with student demographic breakdown including counts, means,
#'   and percentages. See \code{\link{summarize_student_demographics}} for details.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Sets default group_cols if not provided
#'   \item Sets default reg_status_code (registered students only)
#'   \item Filters students using \code{filter_class_list()}
#'   \item Removes data from before Fall 2019 (term < 201980)
#'   \item Calls \code{summarize_student_demographics()} to aggregate
#'   \item Returns demographic summary with percentages
#' }
#'
#' Use this function to answer questions like:
#' \itemize{
#'   \item "What majors are taking MATH 1430 and how has that changed?"
#'   \item "Are we seeing more upperclassmen in intro courses over time?"
#'   \item "Which colleges' students are enrolled in this gen ed course?"
#' }
#'
#' @examples
#' \dontrun{
#' # Analyze major composition of a course over time
#' opt <- list(
#'   course = "BIOL 2305",
#'   group_cols = c("campus", "term", "term_type", "major", "subject_course")
#' )
#' major_breakdown <- rollcall(cedar_students, opt)
#'
#' # Analyze classification changes across all MATH courses
#' opt <- list(
#'   subject = "MATH",
#'   group_cols = c("campus", "term", "student_classification", "subject_course")
#' )
#' class_breakdown <- rollcall(cedar_students, opt)
#' }
#'
#' @seealso
#' \code{\link{summarize_student_demographics}} for the aggregation function,
#' \code{\link{filter_class_list}} for filtering options,
#' \code{\link{plot_rollcall_summary}} for visualization
#'
#' @export
rollcall <- function(students, opt) {
  message("[rollcall.R] Welcome to rollcall!")

  # Set default group_cols if not provided
  if (is.null(opt[["group_cols"]])) {
    message("[rollcall.R] No group_cols specified. Using defaults.")
    opt[["group_cols"]] <- c("campus", "college", "term", "term_type",
                             "student_classification", "major", "subject_course", "course_title", "level")
  }

  # Set default reg_status_code if not provided
  # Note: uses reg_status_code to match filter_class_list's opt_col_map_classlist
  if (is.null(opt[["reg_status_code"]])) {
    message("[rollcall.R] No reg_status_code specified. Using defaults.")
    opt[["reg_status_code"]] <- c("RE", "RS")
  }

  message("[rollcall.R] group_cols: ", paste(opt[["group_cols"]], collapse = ", "))
  message("[rollcall.R] reg_status_code: ", paste(opt[["reg_status_code"]], collapse = ", "))

  # Set the "use exclude list" flag
  message("[rollcall.R] Setting --uel flag to TRUE...")
  opt$uel <- TRUE

  # Filter students based on options
  filtered_students <- filter_class_list(students, opt)

  # Remove students from terms before 201980 (Fall 2019)
  message("[rollcall.R] Removing students pre-201980...")
  filtered_students$term <- as.integer(filtered_students$term)
  filtered_students <- filtered_students %>% filter(term >= 201980)

  # Summarize student demographics
  message("[rollcall.R] Aggregating student demographics...")
  summary <- summarize_student_demographics(filtered_students, opt)

  message("[rollcall.R] Returning summary from rollcall...")
  return(summary)
}


#' Plot Classification Time Series
#'
#' Creates line plots showing the percentage of students in each classification across terms over time.
#' @param rollcall_data A dataframe from summarize_student_demographics containing rollcall data with term info.
#' @param value_column The column to use for y-axis values (default: "term_pct")
#' @param top_n Number of top classifications/majors to display (default: 8)
#' @return A plotly object showing time series lines.
#' @examples
#' plot_time_series(rollcall_data, fill_column = "student_classification", value_column = "term_type_pct", top_n = 6)
plot_time_series <- function(rollcall_data, fill_column = "student_classification", value_column = "term_type_pct", top_n = 5) {
  message("[rollcall.R] Welcome to plot_time_series! Creating time series plot.")
  

  #top_n <- 5
  #fill_column = "Major"
  
  # Debug: Check data structure
  message("[rollcall.R] Creating time series plot for ", fill_column, " using value column: ", value_column)
  message("[rollcall.R] Input data has ", nrow(rollcall_data), " rows and ", ncol(rollcall_data), " columns")
  message("[rollcall.R] Available columns: ", paste(colnames(rollcall_data), collapse = ", "))
  
  # Define columns for plotting and grouping
  plot_cols <- c("term", "subject_course", fill_column, value_column, "count")
  grouping_cols <- c("subject_course", "term", "campus", "college", fill_column)
  
  message("[rollcall.R] Using grouping_cols: ", paste(grouping_cols, collapse = ", "))
  message("[rollcall.R] Using plot_cols: ", paste(plot_cols, collapse = ", "))
  
  # Check required columns
  required_cols <- c(fill_column, "term", value_column, "count")
  missing_cols <- required_cols[!required_cols %in% colnames(rollcall_data)]
  
  if (length(missing_cols) > 0) {
    message("[rollcall.R] Warning: Missing required columns: ", paste(missing_cols, collapse = ", "))
    return(NULL)
  }
  
  # Step 1: Identify top N majors/classifications by summing student counts across all terms
  message("[rollcall.R] Identifying top ", top_n, " ", fill_column, " by total student count...")
  top_categories <- rollcall_data %>%
    group_by(across(all_of(fill_column))) %>%
    summarize(total_students = sum(count, na.rm = TRUE), .groups = 'drop') %>%
    arrange(desc(total_students)) %>%
    slice_head(n = top_n) %>%
    pull(!!sym(fill_column))
  
  message("[rollcall.R] Top ", fill_column, " categories: ", paste(top_categories, collapse = ", "))
  
  # Step 2: Filter data to only include top categories, aggregate by grouping columns
  message("[rollcall.R] Filtering data to top categories and aggregating by grouping columns...")
  time_series_data <- rollcall_data %>% 
    filter(!!sym(fill_column) %in% top_categories) %>%
    group_by(across(all_of(grouping_cols))) %>%
    summarize(
      term_type_pct = mean(!!sym(value_column), na.rm = TRUE),
      count = sum(count, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(term, !!sym(fill_column))

  # Convert term to factor for discrete x-axis (consistent with enrl.R pattern)
  time_series_data$term <- factor(time_series_data$term,
                                   levels = sort(unique(time_series_data$term)),
                                   ordered = TRUE)

  if (nrow(time_series_data) == 0) {
    message("[rollcall.R] No data available for time series plot")
    return(NULL)
  }
  
  message("[rollcall.R] Prepared time series data with ", nrow(time_series_data), " rows for ", length(top_categories), " categories")  
  message("[rollcall.R] Sample data:")
  print(head(time_series_data))
  

  # Create the line plot
  message("[rollcall.R] Creating time series plot...")
  
  time_plot <- plot_ly(
    data = time_series_data,
    x = ~term,
    y = ~term_type_pct,
    color = ~get(fill_column),
    type = "scatter",
    mode = "lines+markers",
    hovertemplate = paste0("<b>%{fullData.name}</b><br>",
                          "Term: %{x}<br>",
                          "Percentage: %{y:.1f}%<br>",
                          "Count: %{customdata}<br>",
                          "<extra></extra>"),
    customdata = ~count,
    line = list(width = 3),
    marker = list(size = 6)
  ) %>%
    layout(
      title = "Trends Over Time",
      xaxis = list(title = "Academic Term", tickangle = -45, type = "category"),
      yaxis = list(title = "Percentage of Course Enrollment"),
      hovermode = "closest",
      legend = list(orientation = "v", x = 1.02, y = 0.5)
    )
  
  
  #time_plot
  
  message("[rollcall.R] Returning time series plot...")
  return(time_plot)
}


#' Plot Rollcall Summary with Consistent Colors Across Terms
#'
#' Wrapper function that creates rollcall plots with consistent color mapping
#' across all term types (fall, spring, summer).
#' @param rollcall_data A dataframe containing rollcall data for all terms.
#' @param fill_column The column name to use for fill aesthetic.
#' @param top_n Number of top categories to include (default: 7)
#' @param filter_column Optional list with column name and values to filter data (e.g., list(column = "campus", values = c("ABQ", "TAOS")))
#' @return A list of plots with consistent colors across term types.
#' @examples
#' consistent_plots <- plot_rollcall_with_consistent_colors(rollcall_data, "major", top_n = 8)
#' # With campus filter:
#' campus_filter <- list(column = "campus", values = c("ABQ"))
#' filtered_plots <- plot_rollcall_with_consistent_colors(rollcall_data, "major", 7, campus_filter)
plot_rollcall_with_consistent_colors <- function(rollcall_data, fill_column = "student_classification", top_n = 7, filter_column = NULL) {
  message("[rollcall.R] Creating rollcall plots with consistent colors for ", fill_column)
  
  # Create consistent color palette across all terms (before filtering)
  color_palette <- create_rollcall_color_palette(rollcall_data, fill_column, top_n)
  
  # Generate plots with consistent colors and optional filtering
  plots <- plot_rollcall_summary(rollcall_data, fill_column, color_palette, filter_column)
  
  message("[rollcall.R] Generated rollcall plots with consistent ", fill_column, " colors")
  return(plots)
}




