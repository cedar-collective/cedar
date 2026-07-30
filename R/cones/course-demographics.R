# course-demographics.R — who is in a course or set of courses
#
# Answers: what is the major and classification breakdown of students in a given
# course (or set of courses), and how has that composition changed over time?
#
# No params required, but results will be very broad without at least a course
# or term filter.


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
  abbreviations <- c(
    "Freshman, 1st Yr, 1st Sem"  = "Freshman",
    "Freshman, 1st Yr, 2nd Sem"  = "Freshman",
    "Freshman, 1st Yr."           = "Freshman",
    "Sophomore, 2nd Yr, 1st Sem" = "Sophomore",
    "Sophomore, 2nd Yr, 2nd Sem" = "Sophomore",
    "Sophomore, 2nd Yr."          = "Sophomore",
    "Junior, 3rd Yr, 1st Sem"    = "Junior",
    "Junior, 3rd Yr, 2nd Sem"    = "Junior",
    "Junior, 3rd Yr."             = "Junior",
    "Senior, 4th Yr, 1st Sem"    = "Senior",
    "Senior, 4th Yr, 2nd Sem"    = "Senior",
    "Senior, 4th Yr."             = "Senior",
    "Senior, 5th Yr. and Beyond" = "Senior 5+",
    "Graduate, Masters"           = "Masters",
    "Graduate, Doctoral"          = "Doctoral",
    "Graduate"                    = "Graduate",
    "Freshman"                    = "Freshman",
    "Sophomore"                   = "Sophomore",
    "Junior"                      = "Junior",
    "Senior"                      = "Senior"
  )

  result <- ifelse(
    classification %in% names(abbreviations),
    abbreviations[classification],
    gsub(",.*$", "", classification)
  )

  return(result)
}


#' Get Major Mix for a Course Set
#'
#' Summarizes the major/program mix for students enrolled in a selected set of
#' courses. Counts are enrollment rows, not unique students, so a student taking
#' two selected courses contributes two seats to the mix. The enrollment-row
#' major code is used as the baseline because it is attached to the course term;
#' same-term primary program records are used when available for cleaner names
#' and pre-major labels.
#'
#' @param students Data frame of student enrollments from cedar_students.
#' @param programs Data frame of program records from cedar_programs.
#' @param opt Options list. Supports course/term/campus/college filters accepted
#'   by filter_class_list(), plus min_n and top_n for display grouping.
#' @return Tibble with major_label, n_enrollments, n_students, pct_enrollments.
get_course_major_mix <- function(students, programs, opt = list()) {
  if (is.null(students) || nrow(students) == 0) {
    return(tibble::tibble())
  }
  if (is.null(programs) || nrow(programs) == 0) {
    return(tibble::tibble())
  }

  required_student_cols <- c("student_id", "term", "subject_course")
  missing_student_cols <- setdiff(required_student_cols, names(students))
  if (length(missing_student_cols) > 0) {
    stop("[course-demographics.R] get_course_major_mix missing student columns: ",
         paste(missing_student_cols, collapse = ", "))
  }

  required_program_cols <- c("student_id", "term", "program_type", "program_name", "major_code")
  missing_program_cols <- setdiff(required_program_cols, names(programs))
  if (length(missing_program_cols) > 0) {
    stop("[course-demographics.R] get_course_major_mix missing program columns: ",
         paste(missing_program_cols, collapse = ", "))
  }

  min_n <- suppressWarnings(as.integer(opt$min_n %||% 5L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 5L
  top_n <- suppressWarnings(as.integer(opt$top_n %||% 10L))
  if (length(top_n) == 0 || is.na(top_n) || top_n < 1L) top_n <- 10L

  filtered <- filter_class_list(students, opt)
  if ("registration_status_code" %in% names(filtered) && !isTRUE(opt$include_all_statuses)) {
    filtered <- filtered %>%
      dplyr::filter(registration_status_code %in% STATUS_REGISTERED)
  }
  if (nrow(filtered) == 0) {
    return(tibble::tibble())
  }

  enrollment_rows <- filtered %>%
    dplyr::mutate(term = as.integer(term)) %>%
    dplyr::distinct(student_id, term, subject_course, .keep_all = TRUE) %>%
    dplyr::mutate(
      class_major_code = if ("major_code" %in% names(.)) as.character(major_code) else NA_character_
    ) %>%
    dplyr::select(student_id, term, subject_course, class_major_code)

  program_rows <- programs %>%
    dplyr::filter(program_type == "Major") %>%
    dplyr::mutate(term = as.integer(term)) %>%
    dplyr::arrange(student_id, term, dplyr::desc(!is.na(program_name) & program_name != "")) %>%
    dplyr::distinct(student_id, term, .keep_all = TRUE) %>%
    dplyr::transmute(
      student_id,
      term,
      program_major_code = major_code,
      program_name,
      is_pre_major = if ("is_pre_major" %in% names(.)) is_pre_major else FALSE
    )

  joined <- enrollment_rows %>%
    dplyr::left_join(program_rows, by = c("student_id", "term")) %>%
    dplyr::mutate(
      program_name = dplyr::na_if(program_name, ""),
      program_major_code = dplyr::na_if(program_major_code, ""),
      class_major_code = dplyr::na_if(class_major_code, "")
    )

  joined$class_major_label <- joined$class_major_code
  if (exists("major_code_to_name") && length(major_code_to_name) > 0) {
    translated <- unname(major_code_to_name[as.character(joined$class_major_code)])
    has_translation <- !is.na(translated) & translated != ""
    joined$class_major_label[has_translation] <- translated[has_translation]
  }
  if (any(is.na(joined$class_major_label) | joined$class_major_label == joined$class_major_code, na.rm = TRUE)) {
    program_code_to_name <- programs %>%
      dplyr::filter(!is.na(major_code), major_code != "", !is.na(program_name), program_name != "") %>%
      dplyr::arrange(major_code, dplyr::desc(program_type == "Major")) %>%
      dplyr::distinct(major_code, .keep_all = TRUE) %>%
      dplyr::select(major_code, program_name)
    program_code_to_name <- stats::setNames(program_code_to_name$program_name, program_code_to_name$major_code)
    translated <- unname(program_code_to_name[as.character(joined$class_major_code)])
    has_translation <- !is.na(translated) & translated != ""
    joined$class_major_label[has_translation] <- translated[has_translation]
  }

  major_counts <- joined %>%
    dplyr::mutate(
      class_major_label = dplyr::na_if(class_major_label, ""),
      major_label = dplyr::case_when(
        !is.na(program_name) & !is.na(is_pre_major) & is_pre_major ~ paste0(program_name, " (pre-major)"),
        !is.na(program_name) ~ program_name,
        !is.na(class_major_label) ~ class_major_label,
        !is.na(program_major_code) ~ program_major_code,
        TRUE ~ "No major code"
      )
    ) %>%
    dplyr::group_by(major_label) %>%
    dplyr::summarize(
      n_enrollments = dplyr::n(),
      n_students = dplyr::n_distinct(student_id),
      n_terms = dplyr::n_distinct(term),
      student_ids = list(unique(student_id)),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(n_enrollments), major_label)

  if (nrow(major_counts) == 0) {
    return(tibble::tibble())
  }

  shown <- major_counts %>%
    dplyr::filter(n_enrollments >= min_n) %>%
    dplyr::slice_head(n = top_n)

  other <- major_counts %>%
    dplyr::anti_join(shown %>% dplyr::select(major_label), by = "major_label")

  if (nrow(other) > 0) {
    shown <- dplyr::bind_rows(
      shown,
      other %>%
        dplyr::summarize(
          major_label = "Other",
          n_enrollments = sum(n_enrollments, na.rm = TRUE),
          n_students = dplyr::n_distinct(unlist(student_ids, use.names = FALSE)),
          n_terms = max(n_terms, na.rm = TRUE),
          student_ids = list(unique(unlist(student_ids, use.names = FALSE))),
          .groups = "drop"
        )
    )
  }

  total_enrollments <- sum(shown$n_enrollments, na.rm = TRUE)
  shown$pct_enrollments <- if (total_enrollments > 0) {
    round(100 * shown$n_enrollments / total_enrollments, 1)
  } else {
    NA_real_
  }

  shown %>%
    dplyr::select(-student_ids) %>%
    dplyr::arrange(dplyr::desc(n_enrollments), major_label)
}


# summarize_student_demographics() and summarize_classifications() moved to
# R/branches/demographics.R — they are consumed by multiple cones
# (course-demographics.R and waitlist.R), so they belong in the branch layer.


#' Create Consistent Color Palette for Demographics Plots
#'
#' Generates a consistent color mapping for categories across multiple plots to ensure
#' the same majors/classifications have the same colors in fall, spring, and summer plots.
#'
#' @param demographics_data A dataframe from \code{summarize_student_demographics()}.
#' @param fill_column The column name to use for color mapping (e.g., "student_classification" or "major")
#' @param top_n Number of top categories to include in color palette (default: 10)
#' @return A named vector of colors where names are category values
#' @examples
#' color_palette <- create_demographics_color_palette(demographics_data, "major", top_n = 8)
create_demographics_color_palette <- function(demographics_data, fill_column, top_n = 10) {
  message("[course-demographics.R] Creating consistent color palette for ", fill_column)

  working_data <- demographics_data

  if (fill_column == "student_classification" && "student_classification" %in% colnames(working_data)) {
    working_data <- working_data %>%
      mutate(student_classification = abbreviate_classification(student_classification))
    message("[course-demographics.R] Abbreviated classification labels for color palette")
  }

  if ("term_type" %in% colnames(working_data)) {
    top_by_term <- working_data %>%
      group_by(term_type, !!sym(fill_column)) %>%
      summarise(term_pct = sum(term_type_pct, na.rm = TRUE), .groups = "drop") %>%
      group_by(term_type) %>%
      slice_max(order_by = term_pct, n = top_n, with_ties = FALSE) %>%
      ungroup()

    all_categories <- top_by_term %>%
      group_by(!!sym(fill_column)) %>%
      summarise(total_pct = sum(term_pct, na.rm = TRUE), .groups = "drop") %>%
      arrange(desc(total_pct)) %>%
      pull(!!sym(fill_column))
  } else {
    all_categories <- working_data %>%
      group_by(!!sym(fill_column)) %>%
      summarise(total_pct = sum(term_type_pct, na.rm = TRUE), .groups = "drop") %>%
      arrange(desc(total_pct)) %>%
      slice_head(n = top_n) %>%
      pull(!!sym(fill_column))
  }

  color_mapping <- build_color_map(all_categories)

  message("[course-demographics.R] Created color palette for ", length(all_categories), " categories: ", paste(all_categories, collapse = ", "))
  return(color_mapping)
}


#' Plot Demographics Summary (Donut Charts)
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
#' @param demographics_data Data frame from \code{summarize_student_demographics()}.
#'   Must contain columns: fill_column, term_type, mean, term_type_pct, campus, college, subject_course
#' @param fill_column Column name to group by (e.g., "student_classification" or "major")
#' @param color_palette Named vector of colors from \code{create_demographics_color_palette()}
#' @param filter_column Optional list with \code{column} and \code{values} for filtering
#'
#' @return Named list of plotly donut charts: fall, spring, summer, by_term
#'
#' @seealso
#' \code{\link{summarize_student_demographics}} for data preparation,
#' \code{\link{create_demographics_color_palette}} for consistent colors,
#' \code{\link{plot_demographics_with_consistent_colors}} for the wrapper function
plot_demographics_summary <- function(demographics_data, fill_column = "student_classification", color_palette = NULL, filter_column = NULL) {
  message("[course-demographics.R] Creating donut chart for demographics using fill column: ", fill_column)

  if (!is.null(filter_column) && !is.null(filter_column$column) && !is.null(filter_column$values)) {
    filter_col  <- filter_column$column
    filter_vals <- filter_column$values

    if (filter_col %in% colnames(demographics_data) && length(filter_vals) > 0) {
      original_rows   <- nrow(demographics_data)
      demographics_data <- demographics_data %>% filter(!!sym(filter_col) %in% filter_vals)
      message("[course-demographics.R] Applied filter on '", filter_col, "' for values: ", paste(filter_vals, collapse = ", "))
      message("[course-demographics.R] Filtered data from ", original_rows, " to ", nrow(demographics_data), " rows")
    } else {
      message("[course-demographics.R] Warning: Filter column '", filter_col, "' not found or no filter values provided")
    }
  }

  message("[course-demographics.R] Input data has ", nrow(demographics_data), " rows and ", ncol(demographics_data), " columns")
  message("[course-demographics.R] Available columns: ", paste(colnames(demographics_data), collapse = ", "))

  if (!fill_column %in% colnames(demographics_data)) {
    message("[course-demographics.R] Warning: Column '", fill_column, "' not found in data.")
    return(NULL)
  }

  if (!"term_type_pct" %in% colnames(demographics_data)) {
    message("[course-demographics.R] Warning: 'term_type_pct' column not found in data")
    return(NULL)
  }

  if (fill_column == "student_classification" && "student_classification" %in% colnames(demographics_data)) {
    demographics_data <- demographics_data %>%
      mutate(student_classification = abbreviate_classification(student_classification))
    message("[course-demographics.R] Abbreviated classification labels for display")
  }

  message("[course-demographics.R] Preparing data for plotting (using pre-calculated averages)...")

  data_for_plot <- demographics_data %>%
    ungroup() %>%
    select(all_of(c(fill_column, "campus", "college", "subject_course", "term_type", "mean", "term_type_pct"))) %>%
    distinct() %>%
    rename(avg_students = mean, avg_pct = term_type_pct) %>%
    arrange(campus, college, subject_course, term_type, desc(avg_pct))

  term_types <- unique(data_for_plot$term_type)
  message("[course-demographics.R] Found ", length(term_types), " term types: ", paste(term_types, collapse = ", "))

  plots_by_term <- list()

  for (tt in term_types) {
    message("[course-demographics.R] Creating plot for ", tt)

    all_term_data <- data_for_plot %>% filter(term_type == tt)

    if (nrow(all_term_data) == 0) {
      message("[course-demographics.R] No data for ", tt)
      next
    }

    term_data <- all_term_data %>%
      slice_max(order_by = avg_students, n = 5, with_ties = FALSE)

    term_data <- term_data %>%
      mutate(
        display_students = round(avg_students, 0),
        custom_text      = paste0(avg_pct, "%\n(", display_students, " avg)")
      )

    plot_colors <- NULL
    if (!is.null(color_palette)) {
      category_values <- term_data[[fill_column]]
      plot_colors     <- color_palette[category_values]

      missing_mask <- is.na(plot_colors)
      if (any(missing_mask)) {
        message("[course-demographics.R] Warning: ", sum(missing_mask), " categories not in palette, assigning fallback color")
        plot_colors[missing_mask] <- "#999999"
      }
      plot_colors <- unname(plot_colors)
      message("[course-demographics.R] Applied custom colors for ", length(plot_colors), " categories in ", tt)
    }

    total_categories <- nrow(all_term_data)
    showing_top_n    <- min(5, total_categories)

    term_plot_interactive <- plot_ly(
      data           = term_data,
      labels         = ~get(fill_column),
      values         = ~avg_students,
      type           = "pie",
      hole           = 0.4,
      text           = ~custom_text,
      textinfo       = "label+text",
      hovertemplate  = paste0("<b>%{label}</b><br>",
                              "Avg Students: %{value:.0f}<br>",
                              "Avg Percentage: %{customdata}%<br>",
                              "<extra></extra>"),
      customdata     = ~avg_pct,
      marker         = list(
        line   = list(color = "white", width = 2),
        colors = plot_colors
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
        legend     = list(orientation = "v", x = 1.1, y = 0.5)
      )

    plots_by_term[[tolower(tt)]] <- term_plot_interactive
  }

  message("[course-demographics.R] Created ", length(plots_by_term), " separate plots")
  message("[course-demographics.R] Returning donut chart(s).")

  return(list(
    fall   = plots_by_term[["fall"]],
    spring = plots_by_term[["spring"]],
    summer = plots_by_term[["summer"]],
    by_term = plots_by_term
  ))
}


#' Get Course Demographics
#'
#' Analyzes the demographic composition (majors, classifications, etc.) of students
#' in a course or set of courses over time. Returns counts, means across terms,
#' and percentages of course enrollment — answering "who is in this course?"
#'
#' @param students Data frame of student enrollments from cedar_students table.
#' @param opt Options list for filtering and grouping:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of columns to group by. If NULL, uses defaults:
#'       campus, college, term, term_type, student_classification, major, subject_course,
#'       course_title, level
#'     \item \code{reg_status_code} - Registration status codes to include (default: STATUS_REGISTERED)
#'     \item \code{course} - Course identifier(s) to filter by
#'     \item \code{term} - Term code(s) to filter by
#'     \item Other filtering options supported by \code{filter_class_list()}
#'   }
#'
#' @return Data frame with student demographic breakdown including counts, means,
#'   and percentages. See \code{\link{summarize_student_demographics}} for column details.
#'
#' @examples
#' \dontrun{
#' # Major composition of a course over time
#' opt <- list(
#'   course     = "BIOL 2305",
#'   group_cols = c("campus", "term", "term_type", "major", "subject_course")
#' )
#' major_breakdown <- get_course_demographics(cedar_students, opt)
#'
#' # Classification breakdown across all MATH courses
#' opt <- list(
#'   subject    = "MATH",
#'   group_cols = c("campus", "term", "student_classification", "subject_course")
#' )
#' class_breakdown <- get_course_demographics(cedar_students, opt)
#' }
#'
#' @seealso
#' \code{\link{summarize_student_demographics}} for the aggregation function,
#' \code{\link{filter_class_list}} for filtering options,
#' \code{\link{plot_demographics_summary}} for visualization
#'
#' @export
get_course_demographics <- function(students, opt) {
  message("[course-demographics.R] Starting course demographics analysis...")

  if (is.null(opt[["group_cols"]])) {
    message("[course-demographics.R] No group_cols specified. Using defaults.")
    opt[["group_cols"]] <- c("campus", "college", "term", "term_type",
                             "student_classification", "major_code", "subject_course", "course_title", "level")
  }

  if (is.null(opt[["reg_status_code"]])) {
    message("[course-demographics.R] No reg_status_code specified. Using defaults.")
    opt[["reg_status_code"]] <- STATUS_REGISTERED
  }

  message("[course-demographics.R] group_cols: ", paste(opt[["group_cols"]], collapse = ", "))
  message("[course-demographics.R] reg_status_code: ", paste(opt[["reg_status_code"]], collapse = ", "))

  opt$uel <- TRUE
  filtered_students <- filter_class_list(students, opt)

  # Exclude terms before Fall 2019 — data quality is inconsistent before this
  message("[course-demographics.R] Removing students pre-201980...")
  filtered_students$term <- as.integer(filtered_students$term)
  filtered_students      <- filtered_students %>% filter(term >= 201980)

  message("[course-demographics.R] Aggregating student demographics...")
  summary <- summarize_student_demographics(filtered_students, opt)

  message("[course-demographics.R] Returning summary from get_course_demographics...")
  return(summary)
}


#' Plot Classification Time Series
#'
#' Creates line plots showing the actual term-level percentage of students in
#' each classification or major across terms over time.
#'
#' @param demographics_data A dataframe from \code{summarize_student_demographics()}.
#' @param fill_column Column to group by (default: "student_classification")
#' @param value_column Column to use for y-axis values (default: "term_pct")
#' @param top_n Number of top categories to display (default: 5)
#' @return A plotly object showing time series lines.
plot_time_series <- function(demographics_data, fill_column = "student_classification", value_column = "term_pct", top_n = 5) {
  message("[course-demographics.R] Creating time series plot for ", fill_column, ".")

  grouping_cols <- c("subject_course", "term", fill_column)

  message("[course-demographics.R] grouping_cols: ", paste(grouping_cols, collapse = ", "))

  required_cols <- c(fill_column, "term", value_column, "count")
  missing_cols  <- required_cols[!required_cols %in% colnames(demographics_data)]

  if (length(missing_cols) > 0) {
    message("[course-demographics.R] Warning: Missing required columns: ", paste(missing_cols, collapse = ", "))
    return(NULL)
  }

  message("[course-demographics.R] Identifying top ", top_n, " ", fill_column, " by total student count...")
  top_categories <- demographics_data %>%
    group_by(across(all_of(fill_column))) %>%
    summarize(total_students = sum(count, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(total_students)) %>%
    slice_head(n = top_n) %>%
    pull(!!sym(fill_column))

  message("[course-demographics.R] Top categories: ", paste(top_categories, collapse = ", "))

  time_series_data <- demographics_data %>%
    filter(!!sym(fill_column) %in% top_categories) %>%
    group_by(across(all_of(grouping_cols))) %>%
    summarize(
      count      = sum(count, na.rm = TRUE),
      registered = if ("registered" %in% names(demographics_data)) sum(registered, na.rm = TRUE) else NA_real_,
      pct        = dplyr::case_when(
        "registered" %in% names(demographics_data) & registered > 0 ~ round(count / registered * 100, 1),
        TRUE ~ round(mean(!!sym(value_column), na.rm = TRUE), 1)
      ),
      .groups    = "drop"
    ) %>%
    arrange(term, !!sym(fill_column))

  time_series_data$term <- factor(time_series_data$term,
                                   levels  = sort(unique(time_series_data$term)),
                                   ordered = TRUE)

  if (nrow(time_series_data) == 0) {
    message("[course-demographics.R] No data available for time series plot")
    return(NULL)
  }

  message("[course-demographics.R] Prepared time series data with ", nrow(time_series_data), " rows.")
  time_series_data <- time_series_data %>%
    dplyr::mutate(term = term_axis_factor(term))
  line_colors <- build_color_map(unique(time_series_data[[fill_column]]))

  plot_title <- if (identical(value_column, "term_pct")) {
    "Actual Term Composition Over Time"
  } else {
    "Trends Over Time"
  }

  time_plot <- plot_ly(
    data          = time_series_data,
    x             = ~term,
    y             = ~pct,
    color         = ~get(fill_column),
    colors        = line_colors,
    type          = "scatter",
    mode          = "lines+markers",
    hovertemplate = paste0("<b>%{fullData.name}</b><br>",
                           "Term: %{x}<br>",
                           "Percentage: %{y:.1f}%<br>",
                           "Count: %{customdata}<br>",
                           "<extra></extra>"),
    customdata    = ~count,
    line          = list(width = 3),
    marker        = list(size = 6)
  ) %>%
    layout(
      title   = plot_title,
      xaxis   = list(title = "Academic Term", tickangle = -45, type = "category"),
      yaxis   = list(title = "Percentage of Course Enrollment"),
      hovermode = "closest",
      legend  = list(orientation = "v", x = 1.02, y = 0.5)
    )

  message("[course-demographics.R] Returning time series plot...")
  return(time_plot)
}


#' Plot Demographics with Consistent Colors Across Terms
#'
#' Wrapper that creates demographics donut charts with a consistent color mapping
#' across all term types (fall, spring, summer).
#'
#' @param demographics_data A dataframe from \code{summarize_student_demographics()}.
#' @param fill_column The column name to use for fill aesthetic.
#' @param top_n Number of top categories to include (default: 7)
#' @param filter_column Optional list with column name and values to filter
#'   (e.g., list(column = "campus", values = c("ABQ")))
#' @return A list of plotly charts with consistent colors across term types.
#' @examples
#' consistent_plots <- plot_demographics_with_consistent_colors(demographics_data, "major", top_n = 8)
plot_demographics_with_consistent_colors <- function(demographics_data, fill_column = "student_classification", top_n = 7, filter_column = NULL) {
  message("[course-demographics.R] Creating demographics plots with consistent colors for ", fill_column)

  color_palette <- create_demographics_color_palette(demographics_data, fill_column, top_n)
  plots         <- plot_demographics_summary(demographics_data, fill_column, color_palette, filter_column)

  message("[course-demographics.R] Generated demographics plots with consistent ", fill_column, " colors")
  return(plots)
}
