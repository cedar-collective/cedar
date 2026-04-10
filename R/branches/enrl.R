#' Calculate Course-Level Enrollment Statistics
#'
#' Summarizes student enrollments for each course by term and term_type, counting
#' registration statuses (registered, dropped, waitlisted) and calculating averages.
#'
#' @param students Data frame of student-level course registration data.
#'   Required columns: campus, college, term, term_type, subject_course, student_id,
#'   registration_status_code
#' @param reg_status Optional character vector of registration status codes to filter by
#'   (e.g., c("RE", "DR")). If NULL (default), all status codes are summarized.
#'
#' @return Data frame with enrollment statistics per course per term. Key columns:
#' \describe{
#'   \item{registered}{Count of registered students (RE, RS codes) for THIS TERM}
#'   \item{registered_mean}{AVERAGE registered count across all terms OF SAME TERM_TYPE.
#'     E.g., if Fall 2023 had 45 and Fall 2024 had 55, registered_mean = 50.
#'     This is used as the denominator for calculating average percentages.}
#'   \item{dr_early, dr_late, dr_all}{Drop counts for this term}
#'   \item{dr_early_mean, dr_late_mean, dr_all_mean}{Average drops across term_type}
#' }
#'
#' @details
#' The "_mean" columns are critical for rollcall analysis. They represent the average
#' enrollment across all terms of the same type (e.g., all falls), providing a stable
#' baseline for calculating "typical" percentages.
#'
#' Calculation flow:
#' 1. Groups by campus, college, subject_course, term, term_type, registration_status_code
#' 2. Counts distinct students per group
#' 3. Regroups by term_type (removing term) to calculate means across terms
#' 4. NAs replaced with 0
#'
#' @examples
#' # Summarize all registration statuses:
#' calc_cl_enrls(students_df)
#' # Summarize only registered and dropped students:
#' calc_cl_enrls(students_df, reg_status = c("RE", "DR"))

calc_cl_enrls <- function(filtered_students, reg_status = NULL) {

  # filtered_students <- load_students()
  #opt <- list()
  #opt[["course"]] <- "HIST 1105"
  #filtered_students <- filter_class_list(students,opt)
  # reg_status <- c("DR")
  # reg_status <- NULL


  reg_stats_summary <- tibble()
  
  message("[enrl.R] Welcome to calc_cl_enrls!")
  
  # get distinct rows within courses; use subject_course to lump all sections topics courses together
  message("[enrl.R] Getting distinct student within courses...")
  cl_enrls <- filtered_students %>%
    group_by(campus, college, term, subject_course) %>%
    distinct(student_id, .keep_all = TRUE)
  
  # count students in each term by reg status code
  message("[enrl.R] Counting students in each campus/college/course/term by reg status code...")
  cl_enrls <- cl_enrls %>% group_by(campus, college, subject_course, registration_status_code, term, term_type) %>%
    summarize(count = n(), .groups="keep") 
  
  # calc mean reg codes per course and term type
  message("[enrl.R] Calculating mean counts across terms...")
  cl_enrls <- cl_enrls %>% group_by(campus, college, subject_course, term_type, registration_status_code) %>%
    mutate(mean = round(mean(count),digits=1))
  
  
  if (is.null(reg_status)) {
    message("[enrl.R] reg_status is NULL; single-pass pivot across all registration codes...")

    # Single-pass: classify and sum all status buckets in one summarize() call.
    # Uses conditional sum() instead of 6 separate filter+merge passes.
    # Zero-count buckets return 0 (not NA) because sum(integer(0)) == 0L.
    reg_stats_summary <- cl_enrls %>%
      group_by(campus, college, subject_course, term, term_type) %>%
      summarize(
        registered = sum(count[registration_status_code %in% STATUS_REGISTERED]),
        dr_early   = sum(count[registration_status_code %in% STATUS_DROP_EARLY]),
        dr_late    = sum(count[registration_status_code %in% STATUS_DROP_LATE]),
        dr_all     = sum(count[registration_status_code %in% STATUS_DROP_ALL]),
        wl_all     = sum(count[registration_status_code %in% c("WL")]),
        cl_total   = sum(count[!registration_status_code %in% c("WL")]),
        .groups    = "keep"
      )

    # Compute cross-term means grouped by term_type (drop term from grouping)
    message("[enrl.R] calculating means across term types...")
    reg_stats_summary <- reg_stats_summary %>%
      group_by(campus, college, subject_course, term_type) %>%
      mutate(across(
        c(registered, dr_early, dr_late, dr_all, cl_total),
        ~ round(mean(.), digits = 2),
        .names = "{.col}_mean"
      ))
  } # end if reg_status is null

  # if given list of reg codes, filter for those
  else if (!is.null(reg_status)) {
    message("[enrl.R] Filtering for status codes: ", reg_status)
    reg_stats_summary <- cl_enrls %>% filter(registration_status_code %in% reg_status)
  }

  message("[enrl.R] calc_cl_enrls returning ",nrow(reg_stats_summary)," rows.")

  return (reg_stats_summary)
}

#' Compress AOP Course Pairs
#'
#' Compresses paired AOP (All Online Programs) course sections into single rows.
#' AOP courses typically consist of a MOPS (Modular Online Pair Section) and a
#' paired online section that are crosslisted. This function combines them into
#' a single row for cleaner reporting and analysis.
#'
#' @param courses Data frame of course sections. Must include columns:
#'   term, crosslist_code, delivery_method, crn, enrolled, total_enrl
#' @param opt Options list (currently unused but kept for consistency)
#'
#' @return Data frame with AOP pairs compressed. Non-AOP courses are unchanged.
#'   Compressed rows have:
#'   \itemize{
#'     \item \code{enrolled} = total_enrl (combined enrollment)
#'     \item \code{sect_enrl} = enrollment of kept section
#'     \item \code{pair_enrl} = enrollment of merged partner section
#'   }
#'
#' @details
#' The compression process:
#' \enumerate{
#'   \item Identifies MOPS delivery method courses (AOP sections)
#'   \item Filters for crosslisted AOP courses (crosslist_code != "0")
#'   \item Groups paired sections by term and crosslist_code
#'   \item Keeps first section (by delivery_method sort order)
#'   \item Combines enrollment: sets enrolled = total_enrl for kept row
#'   \item Adds sect_enrl and pair_enrl columns showing split
#'   \item Merges back with non-AOP courses
#' }
#'
#' AOP sections without a crosslisted partner are left as single sections.
#'
#' @examples
#' \dontrun{
#' # Compress AOP pairs in filtered course data
#' opt <- list(dept = "BIOL", term = "202510")
#' courses_filtered <- filter_DESRs(cedar_sections, opt)
#' courses_compressed <- compress_aop_pairs(courses_filtered, opt)
#' }
#'
#' @seealso \code{\link{get_enrl}} which calls this function when opt$aop = "compress"
compress_aop_pairs <- function(courses, opt) {
  message("[enrl.R] Compressing AOP courses into single row...")
  
  # for clarity, combine aop and twin courses into single entry
  # test to see if we're filtering by dept
  courses <- courses %>% group_by(term, crosslist_code)

  # get just AOP courses
  courses_aop <- courses %>% filter(delivery_method == "MOPS")

  # AOP sections don't necessarily have a partner, so remove those without one
  # TODO: handle case of AOP course having partner, but not being crosslisted
  # might be able to check on course title
  courses_aop <- courses_aop %>% filter(crosslist_code != "0")

  # get pairs of aop and twin section
  aop_pairs <- courses_aop %>% filter(crosslist_code %in% courses_aop$crosslist_code) %>%
    distinct(crn, .keep_all = TRUE) %>%
    group_by(term, crosslist_code)

  # to collapse the aop and online section into one row, get each section's enrollment
  aop_pairs <- aop_pairs %>% mutate(sect_enrl = enrolled, pair_enrl = total_enrl - enrolled)

  # arrange by delivery_method, and take first row of group
  aop_single <- aop_pairs %>% arrange(delivery_method) %>% filter(row_number() == 1)
  # message("aop sections:")
  # print(aop_single)

  # since compressing two sections into one, change enrolled to mimic total_enrl
  # otherwise, compressing effectively deletes the non-aop section enrollment
  aop_single <- aop_single %>% mutate(enrolled = total_enrl)

  # remove all pairs from orig course list
  courses <- courses %>% filter(!(crosslist_code %in% courses_aop$crosslist_code)) %>% distinct(crn, .keep_all = TRUE) %>%
    group_by(term, crosslist_code)
  
  # add all single rows
  courses <- rbind(courses,aop_single)
  
  message("returning compressed aop rows...")
  
  return(courses)
} # end compress_aop_pairs
#' Summarize Courses by Grouping Columns
#'
#' Generic summary function that aggregates course section data by specified
#' grouping columns. Calculates section counts, enrollment statistics, and
#' availability metrics.
#'
#' @param courses Data frame of course sections. Must include columns used in
#'   grouping plus: enrolled, crosslist_code, available, waitlist_count
#' @param opt Options list containing:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of column names to group by.
#'       If NULL, uses default: campus, college, term, term_type, subject,
#'       subject_course, course_title, level, gen_ed_area
#'   }
#'
#' @return Data frame summarized by group_cols with columns:
#'   \describe{
#'     \item{sections}{Total number of sections in group}
#'     \item{xl_sections}{Number of crosslisted sections (crosslist_code != "0")}
#'     \item{reg_sections}{Number of regular (non-crosslisted) sections}
#'     \item{avg_size}{Average enrollment per section (rounded to 1 decimal)}
#'     \item{enrolled}{Total enrollment across all sections}
#'     \item{avail}{Total available seats across all sections}
#'     \item{waiting}{Total waitlist count across all sections}
#'   }
#'   Plus all columns specified in group_cols.
#'
#' @details
#' This function replaces many previous aggregation variants by providing a
#' flexible grouping mechanism. Group by course_title to differentiate topics
#' courses that share the same subject_course code.
#'
#' The function uses \code{group_by_at} with dynamic column selection, making
#' it adaptable to different analysis needs (e.g., department-level, course-level,
#' section-level summaries).
#'
#' @examples
#' \dontrun{
#' # Summarize by course across all terms
#' opt <- list(group_cols = c("subject_course", "course_title"))
#' summary <- summarize_courses(cedar_sections, opt)
#'
#' # Summarize by department and term (default grouping)
#' opt <- list(group_cols = NULL)  # Uses default
#' summary <- summarize_courses(cedar_sections, opt)
#' }
#'
#' @seealso \code{\link{get_enrl}}, \code{\link{aggregate_courses}}
summarize_courses <- function(courses, opt) {
  message("[enrl.R] Summarizing courses with group_cols...")

  # total_enrl must be present — it is set by transform-to-cedar.R (pmax(ENROLLED, XL_ENRL))
  # and preserved through get_enrl()'s select step. If it is missing here, the data was
  # not sourced from cedar_sections or was transformed in a way that dropped the column.
  # Silently substituting enrolled would produce wrong numbers for XL courses with no trace.
  if (!"total_enrl" %in% names(courses)) {
    stop("[enrl.R] summarize_courses: 'total_enrl' column missing. ",
         "Data must come from cedar_sections (via get_enrl). ",
         "Columns present: ", paste(sort(names(courses)), collapse = ", "))
  }

  # set default group_cols
  # group by course_title to differentiate topics courses that use same subject_course
  if (is.null(opt[["group_cols"]])) {
    group_cols <- c("campus", "college", "term", "term_type", "subject", "subject_course", "course_title", "level", "gen_ed_area")
    message("[enrl.R] group_cols is null; using default: ", paste(group_cols, collapse = ", "))
  }
  else {
    group_cols <- opt[["group_cols"]]
    group_cols <- convert_param_to_list(group_cols)
    group_cols <- as.character(group_cols)
    message("[enrl.R] specified grouping by: ", paste(group_cols, collapse = ", "))
  }

  # Validate that all group_cols exist in the data
  missing_cols <- setdiff(group_cols, colnames(courses))
  if (length(missing_cols) > 0) {
    message("[enrl.R] WARNING: Missing columns in group_cols: ", paste(missing_cols, collapse = ", "))
    message("[enrl.R] Available columns: ", paste(colnames(courses), collapse = ", "))
    group_cols <- intersect(group_cols, colnames(courses))
    message("[enrl.R] Adjusted group_cols to: ", paste(group_cols, collapse = ", "))
  }

  if (length(group_cols) == 0) {
    stop("[enrl.R] ERROR: No valid group_cols after validation. Check column names in data.")
  }

  # Main summary across sections
  message("[enrl.R] Starting data with ", nrow(courses), " rows...")
  message("[enrl.R] summarizing enrollments by: ", paste(group_cols, collapse = ", "))
  
  summary <- courses %>% ungroup() %>% group_by_at(group_cols) %>%
    summarize(sections=n(),
      xl_sections=sum(crosslist_code != "0" & crosslist_code != "", na.rm=TRUE),
      reg_sections=sum(crosslist_code == "0" | crosslist_code == "" | is.na(crosslist_code)),
      avg_size=round(mean(enrolled, na.rm=TRUE),digits=1),
      enrolled=sum(enrolled, na.rm=TRUE),
      total_enrl=sum(total_enrl, na.rm=TRUE),
      avail=sum(available, na.rm=TRUE),
      waiting=sum(waitlist_count, na.rm=TRUE),
      .groups="keep")
  
  message("[enrl.R] Summarized to ", nrow(summary), " rows")
  return(summary)
}


#' Aggregate Courses (Wrapper)
#'
#' Wrapper function that validates group_cols parameter and calls summarize_courses().
#' This function ensures that aggregation is only attempted when grouping columns
#' are specified.
#'
#' @param courses Data frame of course sections
#' @param opt Options list. Must contain \code{group_cols} element with column names
#'
#' @return Data frame aggregated by group_cols (see \code{\link{summarize_courses}})
#'
#' @details
#' This is primarily a validation wrapper. It stops execution with an error if
#' group_cols is NULL, ensuring the caller provides explicit grouping instructions.
#'
#' @seealso \code{\link{summarize_courses}} for actual aggregation logic
aggregate_courses <- function(courses, opt) {
  message("[enrl.R] Welcome to aggregate_courses!")

  if (!is.null(opt[["group_cols"]])) {
    message("[enrl.R] opt$group_cols is not null. Summarizing by group_cols...")
    summary <- summarize_courses(courses,opt)
  }
  else {
    message("[enrl.R] ERROR: opt is: ", opt)
    stop("[enrl.R] opt$group_cols is null. Please specify group_cols for aggregation.")
  }
  
  # return the summary DF
  message("[enrl.R] Done aggregating! Returning summary with ", nrow(summary), " rows...")
  return(summary)

} # end aggregate_courses



#' Get Enrollment Summary and Plots for Department Report
#'
#' Creates enrollment analysis and visualizations for department reports. Aggregates
#' enrollment data by course, generates top enrollment charts, and produces class size
#' distribution histograms.
#'
#' @param courses Data frame of course sections from cedar_sections table.
#' @param dept_code Character. Department code to analyze (e.g., "ENGL").
#' @param palette Character. ColorBrewer palette name for plots (e.g., "Set2", "Dark2").
#' @param term_start Integer. First term code to include (e.g., 201980). Fall/spring only —
#'   summers are excluded regardless.
#' @param term_end Integer. Last term code to include (e.g., 202480).
#'
#' @return List with structure:
#'   list(
#'     plots  = list(highest_total_enrl_plot, highest_mean_enrl_plot, highest_mean_histo_plot),
#'     tables = list()
#'   )
#'
#' @details
#' This function performs the following steps:
#' \enumerate{
#'   \item Strips summer terms from the sections data
#'   \item Builds opt list with department filter, term range, and default grouping columns
#'   \item Calls \code{get_enrl()} to filter and aggregate enrollment data
#'   \item Identifies top 10 courses by total and average enrollment
#'   \item Creates bar charts for highest enrollment courses
#'   \item Creates histogram of class size distribution by level
#'   \item Converts histogram to interactive plotly widget
#' }
#'
#' Default grouping columns are: subject, subject_course, course_title, level, gen_ed_area
#'
#' Note: AOP (All Online Programs) courses are compressed by default (opt$x = "compress").
#'
#' @examples
#' \dontrun{
#' result <- get_enrl_for_dept_report(cedar_sections, "ENGL", "Set2", 201980, 202480)
#' result$plots$highest_total_enrl_plot
#' }
#'
#' @seealso \code{\link{get_enrl}}, \code{\link{summarize_courses}}
get_enrl_for_dept_report <- function(courses, dept_code, palette, term_start, term_end) {

  message("[enrl.R] Welcome to get_enrl_for_dept_report!")

  # ── Derive a human-readable window label for axis titles ─────────────────────
  # Term codes are YYYYTT; extract the 4-digit year from each end of the window.
  start_yr <- as.integer(substr(as.character(term_start), 1, 4))
  end_yr   <- as.integer(substr(as.character(term_end),   1, 4))
  window_label <- if (start_yr == end_yr) as.character(start_yr) else paste0(start_yr, "\u2013", end_yr)

  # ── Strip summers before any filtering ───────────────────────────────────────
  # Summer term codes end in 60 (e.g., 202060). Enrollment patterns in summer
  # are very different from fall/spring and would skew averages if included.
  courses <- filter_out_summer(courses, "term")

  myopt <- list()
  myopt$dept <- dept_code
  myopt$term <- paste0(term_start, "-", term_end)   # range filter: "201980-202480"
  myopt$group_cols <- c("subject", "subject_course", "course_title", "level", "gen_ed_area")
  myopt$x <- "compress"
  myopt$uel <- TRUE

  message("[enrl.R] getting enrollment data via get_enrl (", window_label, ", no summers)...")
  summary_across_terms <- get_enrl(courses, myopt)  # filter, aggregate, etc

  # for inspection, rank by avg size across terms or total enrolled
  highest_total_enrl <- summary_across_terms  %>% ungroup() %>% arrange(desc(enrolled)) %>% slice_head(n=10)
  highest_mean_enrl <- summary_across_terms   %>% ungroup() %>% arrange(desc(avg_size))  %>% slice_head(n=10)

  highest_total_enrl_plot <- highest_total_enrl %>%
    mutate(course_title = fct_reorder(course_title, enrolled)) %>%
    ggplot(aes(y=course_title, x=enrolled)) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(stat="identity") +
    ylab("Course") + xlab(paste0("Total Enrollment (", window_label, ")"))

  highest_mean_enrl_plot <- highest_mean_enrl %>%
    mutate(course_title = fct_reorder(course_title, avg_size)) %>%
    ggplot(aes(y=course_title, x=avg_size)) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(stat="identity") +
    ylab("Course") + xlab(paste0("Mean Section Size (", window_label, ")"))


  # histogram of avg class sizes
  highest_mean_enrl <- summary_across_terms  %>% ungroup() %>% arrange(desc(avg_size))

  highest_mean_histo_plot <- highest_mean_enrl %>%
    mutate(course_title = fct_reorder(course_title, avg_size)) %>%
    ggplot(aes(x=avg_size)) +
    #ggtitle(plot_title) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_histogram(aes(fill=level),bins = 30) +
    scale_fill_brewer(palette=palette) +
    ylab("Number of courses") + xlab(paste0("Avg section size (", window_label, ")"))
  
  highest_mean_histo_plot <- ggplotly(highest_mean_histo_plot) %>% 
    layout(legend = list(orientation = 'h', x = 0.3, y = -.3),
           xaxis = list(standoff = -1))
  
  
  list(
    plots = list(
      highest_total_enrl_plot = highest_total_enrl_plot,
      highest_mean_enrl_plot  = highest_mean_enrl_plot,
      highest_mean_histo_plot = highest_mean_histo_plot
    ),
    tables = list(
      enrl_summary = summary_across_terms  # full summary; rebuild derives top-10 slices and histogram
    )
  )
}


#' Create Enrollment Plot from Class List Data
#'
#' Generates an interactive enrollment visualization from student class list (CL)
#' registration statistics. Creates a faceted bar chart showing enrollment by
#' term and campus, with courses distinguished by color.
#'
#' @param reg_stats_summary Data frame of registration statistics aggregated from
#'   class list data. Expected columns include:
#'   \itemize{
#'     \item \code{term} - Term code
#'     \item \code{registered} - Number of registered students
#'     \item \code{subject_course} - Course identifier (e.g., "ENGL 1110")
#'     \item \code{campus} - Campus location
#'   }
#' @param opt Options list (currently unused but kept for consistency with other
#'   enrollment plotting functions)
#'
#' @return Named list containing one element:
#'   \itemize{
#'     \item \code{cl_enrl} - Interactive plotly bar chart (or NULL if no data)
#'   }
#'
#' @details
#' The function creates a bar chart with:
#' \itemize{
#'   \item X-axis: Term (angled 45 degrees)
#'   \item Y-axis: Student count
#'   \item Fill color: Course (subject_course)
#'   \item Facets: Campus (fixed scales)
#'   \item Interactive hover information via plotly
#'   \item Horizontal legend positioned at bottom
#' }
#'
#' If the input data frame is empty (0 rows), returns NULL for the plot.
#'
#' @examples
#' \dontrun{
#' # After calculating CL enrollment statistics
#' reg_stats <- calc_cl_enrls(students)
#' plots <- make_enrl_plot_from_cls(reg_stats, opt = list())
#' plots$cl_enrl  # Display the interactive plot
#' }
#'
#' @seealso \code{\link{make_enrl_plot}} for enrollment plots from section-level data
make_enrl_plot_from_cls <- function(reg_stats_summary, opt) {
  message("[enrl.R] Welcome to make_enrl_plot_from_cls!")

  plots <- list()
  
  if (nrow(reg_stats_summary) > 0) {
    # Convert term to factor for discrete x-axis
    reg_stats_summary$term <- factor(reg_stats_summary$term, levels = sort(unique(reg_stats_summary$term)), ordered = TRUE)
    
    plot <- ggplot(reg_stats_summary, aes(x = term, y = registered,
                                         fill = subject_course,
                                         group = subject_course)) +
      geom_bar(stat = "identity") +
      facet_wrap(~ campus, scales = "fixed") +
      labs(title = "Enrollment by Campus", x = "Term", y = "Student Count", fill = "Course") +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    plots$cl_enrl <- ggplotly(plot) %>% layout(legend = list(orientation = 'h', x = 0.3, y = -.3))
  } else {
    plots$cl_enrl <- NULL
  }
  
  plots$cl_enrl
  
  return(plots)
}



#' Create Enrollment Plot from Aggregated Data
#'
#' Generates an interactive line chart showing enrollment trends over time from
#' pre-aggregated enrollment summary data. Creates faceted visualizations with
#' flexible grouping and optional faceting by any categorical field.
#'
#' @param summary Data frame of aggregated enrollment data (output from \code{get_enrl()}).
#'   Must include columns specified in \code{opt$group_cols}, plus \code{enrolled}.
#' @param opt Options list containing:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of grouping columns. MUST include
#'       "term" and at least one other column (required)
#'     \item \code{facet_field} - Optional field to facet by (e.g., "campus", "level")
#'     \item \code{facet_scales} - Facet scale behavior: "fixed", "free", "free_x", "free_y"
#'       (default: "fixed")
#'     \item \code{facet_ncol} - Number of facet columns (default: NULL for auto)
#'   }
#'
#' @return Named list containing one element:
#'   \itemize{
#'     \item \code{enrl} - Interactive plotly line chart (or NULL if invalid data/opts)
#'   }
#'
#' @details
#' This function creates an enrollment trend visualization with the following features:
#' \itemize{
#'   \item Line chart with enrollment over time (term on x-axis)
#'   \item Lines colored/grouped by the first non-term column in group_cols
#'   \item Optional faceting by any categorical field (campus, level, etc.)
#'   \item Interactive plotly widget with hover details
#'   \item Horizontal legend at bottom
#'   \item 45-degree angled x-axis labels
#' }
#'
#' The function performs validation and will return NULL if:
#' \itemize{
#'   \item summary is missing or not a data frame
#'   \item group_cols is NULL
#'   \item group_cols doesn't include "term"
#'   \item group_cols has fewer than 2 elements
#'   \item summary data frame has 0 rows
#' }
#'
#' @examples
#' \dontrun{
#' # Basic enrollment trend by course
#' opt <- list(
#'   term = c("202310", "202320", "202410"),
#'   group_cols = c("term", "subject_course")
#' )
#' summary <- get_enrl(cedar_sections, opt)
#' plots <- make_enrl_plot(summary, opt)
#' plots$enrl
#'
#' # Faceted by campus with free y-axis scales
#' opt$facet_field <- "campus"
#' opt$facet_scales <- "free_y"
#' opt$facet_ncol <- 2
#' plots <- make_enrl_plot(summary, opt)
#' }
#'
#' @seealso \code{\link{get_enrl}}, \code{\link{make_enrl_plot_from_cls}}
make_enrl_plot <- function(summary, opt) {
  message("[enrl.R] Welcome to make_enrl_plot!")

  # create empty list of plots
  plots <- list()

  # Validate input
  if (missing(summary) || !is.data.frame(summary)) {
    message("[enrl.R] Cannot create plot: Invalid summary data.")
    return(NULL)
  }

  message("[enrl.R] Data shape: ", nrow(summary), " rows")
  message("[enrl.R] Columns: ", paste(colnames(summary), collapse = ", "))

  # Validate group_cols
  group_cols <- opt$group_cols
  if (is.null(group_cols) || !("term" %in% group_cols) || length(group_cols) < 2) {
    message("[enrl.R] Cannot create plot: opt$group_cols must include 'term' and at least one other column name.")
    return(NULL)
  }
# The other grouping column (besides term)
  other_group <- setdiff(group_cols, "term")[1]
  message("[enrl.R] Grouping by: ", other_group)

  # Facet settings from opt (optional)
  facet_field <- opt[["facet_field"]]
  
  # TODO make more dynamic with Shiny inputs
  facet_scales <- "fixed"
  facet_ncol <- NULL

  if (!is.null(facet_field)) {
    message("[enrl.R] Faceting enrollment plot by field: ", facet_field)
  }
  if (!is.null(opt[["facet_scales"]])) facet_scales <- opt[["facet_scales"]]
  if (!is.null(opt[["facet_ncol"]])) facet_ncol <- as.integer(opt[["facet_ncol"]])

  # Enrollment plot
  message("[enrl.R] Creating Enrollment plot...")
  if (nrow(summary) > 0) {
    # Convert term to factor for discrete x-axis
    summary$term <- factor(summary$term, levels = sort(unique(summary$term)), ordered = TRUE)
    
    plot <- ggplot(summary, aes(x = term, y = enrolled, group = .data[[other_group]], color = .data[[other_group]])) +
      geom_line(stat = "identity") +
      labs(title = "Enrollment by Group", x = "Term", y = "Student Count") +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    
    # apply facet if requested and valid
    if (!is.null(facet_field) && facet_field %in% colnames(summary)) {
      if (is.null(facet_ncol)) {
        plot <- plot + facet_wrap(vars(.data[[facet_field]]), scales = facet_scales)
      } else {
        plot <- plot + facet_wrap(vars(.data[[facet_field]]), scales = facet_scales, ncol = facet_ncol)
      }
      message("[enrl.R] Faceting enrollment plot by: ", facet_field, " (scales=", facet_scales, ", ncol=", facet_ncol, ")")
    }

    plots$enrl <- ggplotly(plot) %>% layout(legend = list(orientation = 'h', x = 0.3, y = -.3))
  } else {
    plots$enrl <- NULL
  }

#plots$enrl

message("[enrl.R] returning plots...")
return (plots)
}



#' Get Enrollment Data
#'
#' Main entry point for enrollment analysis. Filters course sections according to
#' specified criteria, handles missing columns gracefully, optionally compresses
#' AOP (All Online Programs) course pairs, and can aggregate data by specified
#' grouping columns.
#'
#' @param courses Data frame of course sections from cedar_sections table.
#'   Must include columns: campus, college, department, term, subject_course, etc.
#' @param opt List of filtering and processing options:
#'   \itemize{
#'     \item \code{dept} - Department code(s) to filter by
#'     \item \code{term} - Term code(s) to filter by
#'     \item \code{campus} - Campus code(s) to filter by
#'     \item \code{status} - Course status (default: "A" for active)
#'     \item \code{uel} - Use exclude list (default: TRUE)
#'     \item \code{aop} - AOP compression mode ("compress" to compress paired sections)
#'     \item \code{group_cols} - Vector of column names to group by for aggregation
#'   }
#'
#' @return Data frame of enrollment data. If \code{opt$group_cols} is specified,
#'   returns aggregated summary with columns: sections, xl_sections, reg_sections,
#'   avg_size, enrolled, avail, waiting. Otherwise returns section-level data
#'   with columns dynamically selected based on availability.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Validates options and sets defaults (status = "A", uel = TRUE)
#'   \item Filters courses using \code{filter_DESRs()} with provided options
#'   \item Dynamically selects columns that exist in the data
#'   \item Computes derived columns if source columns exist:
#'     \itemize{
#'       \item \code{available} = capacity - enrolled
#'       \item \code{total_enrl} = copy of enrolled (if crosslist data missing)
#'     }
#'   \item Optionally compresses AOP course pairs into single rows
#'   \item Removes duplicate rows and sorts consistently
#'   \item Optionally aggregates by \code{group_cols} using \code{summarize_courses()}
#' }
#'
#' Missing columns are handled gracefully - the function will compute derived
#' columns when possible or create placeholders to ensure downstream code works.
#'
#' @examples
#' \dontrun{
#' # Get section-level enrollment for a department
#' opt <- list(dept = "HIST", term = "202510", status = "A")
#' enrl_data <- get_enrl(cedar_sections, opt)
#'
#' # Get aggregated enrollment by course
#' opt <- list(
#'   dept = "HIST",
#'   group_cols = c("campus", "subject_course", "course_title", "term")
#' )
#' summary_data <- get_enrl(cedar_sections, opt)
#'
#' # Compress AOP course pairs
#' opt <- list(dept = "BIOL", aop = "compress")
#' compressed_data <- get_enrl(cedar_sections, opt)
#' }
#'
#' @seealso
#' \code{\link{filter_DESRs}} for filtering options,
#' \code{\link{summarize_courses}} for aggregation,
#' \code{\link{compress_aop_pairs}} for AOP compression
#'
#' @export
get_enrl <- function(courses, opt) {
  message("[enrl.R] Welcome to get_enrl!")

# check for old aggregate flag until totally phased out
  agg_by <- opt$aggregate
  if (!is.null(agg_by)) {
    stop("[enrl.R] ERROR: old aggregate param detected: ", agg_by)
  }

  # default status to A for active courses
  if (is.null(opt$status)) {
    message("[enrl.R] setting default status to A (active courses only.)")
    opt$status <- "A"
  }

  # default to use exclude list
  if (is.null(opt$uel)) {
    message("[enrl.R] setting default to use exclude list (uel=TRUE).")
    opt$uel <- TRUE
  }
  
  # filter courses according to options
  message("[enrl.R] filtering courses (via filter_DESRs) according to options...")
  courses <- filter_DESRs(courses, opt)

  # Combined courses (C-suffix like BIOL 2110C) have multiple CRNs per subject_course,
  # one per lab section. After the crosslist "home" filter keeps only the primary CRN,
  # that CRN's `enrolled` holds one lab section's count (~17) while `total_enrl` holds
  # the correct course-level enrollment (~51). Replace enrolled with total_enrl for
  # combined courses so downstream sums (in summarize_courses, dashboard, etc.) are correct.
  #
  # IMPORTANT: Only apply when crosslist="home" has filtered to primary CRNs.
  # Without that filter, all CRNs remain and their enrolled values already sum to
  # total_enrl naturally (16+16+15 = 47). Correcting without the filter would
  # inflate each row to total_enrl, causing triple-counting.
  if ("is_combined" %in% colnames(courses) &&
      !is.null(opt$crosslist) && opt$crosslist == "home") {
    n_combined_fixed <- sum(courses$is_combined & courses$enrolled != courses$total_enrl, na.rm = TRUE)
    if (n_combined_fixed > 0) {
      message("[enrl.R] Correcting enrolled → total_enrl for ", n_combined_fixed, " combined-course rows")
    }
    courses <- courses %>%
      mutate(enrolled = ifelse(is_combined, total_enrl, enrolled))
  }

  # define standard columns to keep
  # Build list dynamically based on what exists in the data
  desired_cols <- c("campus", "college", "department", "term", "term_type", "crn", "subject", "subject_course", "section", "level", "course_title", "delivery_method", "instructor_name", "job_cat", "enrolled", "total_enrl", "crosslist_role", "crosslist_external", "crosslist_subject", "crosslist_code", "crosslist_partners", "is_split", "split_sections", "is_combined", "available", "waitlist_count", "gen_ed_area", "part_term")

  # Only keep columns that actually exist in the data
  select_cols <- desired_cols[desired_cols %in% colnames(courses)]

  # Compute missing derived columns if possible
  if (!"available" %in% colnames(courses) && all(c("capacity", "enrolled") %in% colnames(courses))) {
    message("[enrl.R] Computing 'available' from capacity - enrolled...")
    courses <- courses %>% mutate(available = capacity - enrolled)
    select_cols <- c(select_cols, "available")
  }

  # If total_enrl doesn't exist, use enrolled as fallback
  if (!"total_enrl" %in% colnames(courses) && "enrolled" %in% colnames(courses)) {
    message("[enrl.R] Computing 'total_enrl' as copy of enrolled (no crosslist data)...")
    courses <- courses %>% mutate(total_enrl = enrolled)
    select_cols <- c(select_cols, "total_enrl")
  }

  # If crosslist columns don't exist, create placeholder columns
  if (!"crosslist_code" %in% colnames(courses)) {
    message("[enrl.R] Adding placeholder 'crosslist_code' column (no crosslist data)...")
    courses <- courses %>% mutate(crosslist_code = "0")
    select_cols <- c(select_cols, "crosslist_code")
  }

  if (!"crosslist_subject" %in% colnames(courses)) {
    message("[enrl.R] Adding placeholder 'crosslist_subject' column (no crosslist data)...")
    courses <- courses %>% mutate(crosslist_subject = "")
    select_cols <- c(select_cols, "crosslist_subject")
  }

  message("[enrl.R] selecting columns: ", paste(select_cols, collapse = ", "))

  ### AOP COMPRESSION
  if (!is.null(opt$aop) && opt$aop == "compress") {
    message("[enrl.R] compressing AOP pairs...")
    courses <- compress_aop_pairs(courses,opt) 
    select_cols <- c(select_cols, "sect_enrl","pair_enrl")
    courses <- courses %>% select(all_of(select_cols))
  }
  else {
    message("[enrl.R] leaving AOP pairs alone...")
    courses <- courses %>% select(all_of(select_cols))
  }
  
  # courses get listed multiple times b/c of crosslisting (inc aop, but also in general)
  # also, a course can also be listed multiple times depending on the lecture/recitation model (b/c of XL_CRSE column)
  
  # remove dupes since we have final columns
  # Build arrange columns dynamically based on what exists
  # campus + college are the primary grouping; detail cols follow the crosslist sort
  group_arrange_cols <- c("campus", "college")
  detail_arrange_cols <- c("subject_course", "course_title", "term_type")
  if ("pt" %in% colnames(courses)) {
    detail_arrange_cols <- c(detail_arrange_cols, "pt")
  }
  detail_arrange_cols <- c(detail_arrange_cols, "delivery_method", "instructor_name")

  courses <- courses %>% distinct()

  if ("crosslist_role" %in% colnames(courses)) {
    # Partner crosslists sort to the bottom within each campus/college grouping
    courses <- courses %>%
      arrange(
        across(all_of(group_arrange_cols)),
        coalesce(crosslist_role == "partner", FALSE),
        across(all_of(detail_arrange_cols))
      )
  } else {
    courses <- courses %>%
      arrange(across(all_of(c(group_arrange_cols, detail_arrange_cols))))
  }
  
  # check if aggregating
  if(!is.null(opt$aggregate) || !is.null(opt$group_cols)) {
    courses <- aggregate_courses(courses, opt)
  } else {
    message("[enrl.R] No aggregating!")
  }

  message("[enrl.R] All done in get_enrl! Returning data with ", nrow(courses) ," rows...\n")
  return(courses)
  
} # end get_enrl function


###################################
# LOW ENROLLMENT DASHBOARD FUNCTIONS
###################################

#' Get courses below enrollment threshold
#'
#' Identifies courses with enrollment below a specified threshold, grouped by
#' campus, department, course title, and instructional method.
#'
#' @param courses Data frame of course sections (DESRs)
#' @param opt Options list with filtering parameters
#' @param threshold Numeric enrollment threshold (default 15)
#'
#' @return Data frame of low-enrollment courses with enrollment history
#' Count active sections and total enrollment per course
#'
#' Aggregates cedar_sections to one row per (term, subject_course, course_title,
#' campus), counting active home sections and summing total enrollment. Crosslist
#' partner rows and cancelled sections are excluded so each course is counted once.
#'
#' Designed to be reusable across any tab or report that needs "how many sections
#' is this course running and how many students are enrolled" — low-enrollment
#' alerts, dashboard summaries, comparison views, etc. Join the result back to a
#' course-level table on (term, subject_course, course_title, campus).
#'
#' @param sections Data frame of course sections (cedar_sections).
#'   Must include: status, crosslist_group, crosslist_primary, term,
#'   subject_course, course_title, campus, total_enrl.
#'
#' @return Data frame with columns:
#'   \itemize{
#'     \item \code{term} — term code
#'     \item \code{subject_course} — e.g. "HIST 1110"
#'     \item \code{course_title} — full course title (needed to distinguish topics courses)
#'     \item \code{campus} — campus code
#'     \item \code{n_sections} — count of active home sections
#'     \item \code{course_enrl} — sum of total_enrl across those sections
#'   }
#'
#' @examples
#' counts <- get_course_section_counts(cedar_sections)
#' low_enrl <- low_enrl %>%
#'   left_join(counts, by = c("term", "subject_course", "course_title", "campus")) %>%
#'   mutate(n_sections = coalesce(n_sections, 1L),
#'          course_enrl = coalesce(course_enrl, total_enrl))
get_course_section_counts <- function(sections) {
  sections %>%
    filter(status == "A") %>%
    filter(is.na(crosslist_group) | crosslist_role %in% c("home", "internal")) %>%
    group_by(term, subject_course, course_title, campus) %>%
    summarize(
      n_sections  = n(),
      course_enrl = sum(total_enrl, na.rm = TRUE),
      .groups = "drop"
    )
}


get_low_enrollment_courses <- function(courses, opt, threshold = 15, level_filter = NULL) {
  message("[enrl.R] Getting low enrollment courses (threshold: ", threshold, ")...")

  # Apply level filter if specified (e.g., "lower", "upper", "split", "grad")
  if (!is.null(level_filter)) {
    message("[enrl.R] Applying level filter: ", paste(level_filter, collapse = ", "))
    opt$level <- level_filter
  }

  # default status to A for active courses
  message("[enrl.R] setting opt status to A (active courses only.)")
  opt$status <- "A"

  # default to use exclude list
  message("[enrl.R] setting opt to use exclude list (uel=TRUE).")
  opt$uel <- TRUE
  
  # HOME leaves one row per all cross-dept xled sections in courses data
  # it's in the "home" dept and with total_enrl as sum of xlisted sections (OR XL_ENRL)
  # we want to filter out non-home xl'ed courses since enrollments tend to be quite small
  opt[["crosslist"]] <- "home"
  message("[enrl.R] setting opt crosslist to HOME to keep only XLed sections in home unit.")
  
  # filter courses
  # since we care about low enrolled sections--not aggregates--don't summarize (ie don't call get_enrl). 
  filtered_courses <- filter_DESRs(courses, opt)
  
  # filter for courses below threshold
  low_enrl <- filtered_courses %>%
    filter(total_enrl < threshold) %>%
    arrange(campus, department, course_title, total_enrl)

  message("[enrl.R] Found ", nrow(low_enrl), " low enrollment courses below threshold.")
  return(low_enrl)
}



#' Get enrollment concerns for a future term
#'
#' Analyzes a future term's scheduled courses against historical enrollment
#' patterns from prior terms of the same type (fall/spring/summer). Returns
#' each scheduled course with its historical average enrollment, trend, and
#' history text for display in the concerns tab.
#'
#' @param courses Data frame of course sections (cedar_sections)
#' @param opt Options list with filters (term, course_campus, dept, etc.)
#' @param n_history_terms Number of prior same-type terms to average (default 4)
#'
#' @return Data frame with schedule + historical stats per course
get_enrollment_concerns <- function(courses, opt, n_history_terms = 4) {
  future_term <- opt$term
  message("[enrl.R] Getting enrollment concerns for future term: ", future_term)

  # 1. Get scheduled courses for the future term
  opt$status <- "A"
  opt$uel <- TRUE
  opt[["crosslist"]] <- "home"
  scheduled <- filter_DESRs(courses, opt)

  if (nrow(scheduled) == 0) {
    message("[enrl.R] No courses scheduled for future term.")
    return(NULL)
  }

  # 2. Aggregate to course-level per campus (one row per subject_course + course_title + campus).
  #    Include course_title to differentiate topics courses with same subject_course.
  #    Take the first value of descriptive columns; sum enrollment and count sections.
  scheduled_courses <- scheduled %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      level = first(level),
      is_split = any(is_split),
      department = first(department),
      split_sections = if ("split_sections" %in% names(.)) first(na.omit(split_sections)) else NA_character_,
      n_sections = n(),
      current_enrl = sum(total_enrl, na.rm = TRUE),
      .groups = "drop"
    )

  message("[enrl.R] Found ", nrow(scheduled_courses), " unique courses on future schedule.")

  # 3. Determine term type for historical matching
  term_type <- get_term_type(future_term)
  message("[enrl.R] Matching against historical '", term_type, "' terms.")

  # 4. Pull historical data: same term_type, home sections, ALL statuses.
  #    Including cancelled sections lets the history show when a course was
  #    scheduled but later cancelled (displayed as "C" in history text).
  #    Exclude shell sections: active with 0 enrollment and no instructor —
  #    these are placeholder sections left in the schedule build, not real offerings.
  hist_data <- courses %>%
    filter(
      is.na(crosslist_group) | crosslist_role %in% c("home", "internal"),
      term_type == !!term_type,
      term != as.integer(future_term),
      !(status == "A" & total_enrl == 0 &
        (is.na(instructor_name) | instructor_name %in% c("NA, NA", "")))
    )

  # 5. Aggregate historical enrollment to course-level per term + campus + course_title.
  #    Include course_title to differentiate topics courses with same subject_course.
  #    Track whether each term had active sections or was fully cancelled.
  hist_by_term <- hist_data %>%
    group_by(subject_course, course_title, campus, term) %>%
    summarize(
      has_active = any(status == "A"),
      term_enrl = sum(total_enrl[status == "A"], na.rm = TRUE),
      .groups = "drop"
    )

  # 6. Keep only the most recent n_history_terms per course+campus+title
  hist_recent <- hist_by_term %>%
    group_by(subject_course, course_title, campus) %>%
    arrange(desc(term)) %>%
    slice_head(n = n_history_terms) %>%
    arrange(term) %>%
    ungroup()

  # 7. Compute averages (active terms only), trend, and history text.
  #    Cancelled terms appear in history_text as "C" but don't affect avg/trend.
  hist_stats <- hist_recent %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      avg_enrl = {
        active_enrl <- term_enrl[has_active]
        if (length(active_enrl) > 0) round(mean(active_enrl, na.rm = TRUE), 1) else NA_real_
      },
      n_prior_terms = sum(has_active),
      n_cancelled = sum(!has_active),
      min_enrl = if (any(has_active)) min(term_enrl[has_active], na.rm = TRUE) else NA_real_,
      max_enrl = if (any(has_active)) max(term_enrl[has_active], na.rm = TRUE) else NA_real_,
      trend_slope = {
        active_enrl <- term_enrl[has_active]
        if (length(active_enrl) >= 2) {
          coef(lm(active_enrl ~ seq_along(active_enrl)))[2]
        } else {
          NA_real_
        }
      },
      history_text = paste(
        ifelse(has_active, paste0(term, ": ", term_enrl), paste0(term, ": C")),
        collapse = " \u2192 "
      ),
      .groups = "drop"
    )

  # 8. Compute trend direction label
  hist_stats <- hist_stats %>%
    mutate(
      trend = case_when(
        is.na(trend_slope)  ~ "\u2014",
        trend_slope > 1     ~ "\u2191 up",
        trend_slope < -1    ~ "\u2193 down",
        TRUE                ~ "\u2194 stable"
      )
    )

  # 9. Join scheduled courses with historical stats
  result <- scheduled_courses %>%
    left_join(hist_stats, by = c("subject_course", "course_title", "campus")) %>%
    mutate(
      avg_enrl = coalesce(avg_enrl, NA_real_),
      n_prior_terms = coalesce(n_prior_terms, 0L),
      history_text = coalesce(history_text, "No prior history"),
      trend = coalesce(trend, "\u2014")
    )

  message("[enrl.R] Enrollment concerns ready: ", nrow(result), " courses (",
          sum(result$n_prior_terms > 0), " with history, ",
          sum(result$n_prior_terms == 0), " new).")
  return(result)
}


#' Get enrollment history for a specific course
#'
#' Retrieves the last N terms of enrollment data for a specific course offering.
#'
#' @param courses Data frame of course sections (DESRs)
#' @param campus Campus code
#' @param dept Department code
#' @param subj_crse Subject and course number (e.g., "HIST 1105")
#' @param crse_title Course title
#' @param im Instructional method code
#' @param n_terms Number of historical terms to retrieve (default 3)
#'
#' @return Data frame with TERM and enrolled columns
get_course_enrollment_history <- function(courses, campus, dept, subj_crse, crse_title, im,
                                         n_terms = 4, exclude_term = NULL) {
  message("[enrl.R] Getting enrollment history for: ", crse_title, " - ", subj_crse)

  # Filter for specific course. Delivery method is intentionally excluded because
  # courses frequently change delivery method across terms (e.g., ENH -> blank),
  # and matching on it produces misleading "no history" results.
  # Include all statuses so cancelled terms appear in history as "C".
  # Exclude shell sections (active, 0 enrollment, no instructor assigned).
  course_history <- courses %>%
    filter(
      campus == !!campus,
      department == !!dept,
      subject_course == !!subj_crse,
      course_title == !!crse_title,
      !(status == "A" & total_enrl == 0 &
        (is.na(instructor_name) | instructor_name %in% c("NA, NA", "")))
    )

  # Exclude current term so history shows only prior terms
  if (!is.null(exclude_term)) {
    course_history <- course_history %>% filter(term != exclude_term)
  }

  # Deduplicate crosslisted rows: keep primary CRN per XL group + all non-XL rows.
  # Then use total_enrl (correct for combined C-suffix courses) instead of enrolled.
  course_history <- course_history %>%
    filter(is.na(crosslist_group) | crosslist_role %in% c("home", "internal")) %>%
    group_by(term) %>%
    summarize(
      has_active = any(status == "A"),
      enrolled = sum(total_enrl[status == "A"], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(term)) %>%
    slice_head(n = n_terms) %>%
    arrange(term)

  message("[enrl.R] Found ", nrow(course_history), " historical terms")
  return(course_history)
}


#' Create enrollment history string for display
#'
#' Generates a text representation of enrollment history (e.g., "12 → 10 → 8")
#'
#' @param history_data Data frame with TERM and enrolled columns
#'
#' @return Character string with enrollment trend
format_enrollment_history <- function(history_data) {
  if (nrow(history_data) == 0) return("No history")

  # Show "C" for cancelled terms, enrollment count for active terms
  if ("has_active" %in% names(history_data)) {
    labels <- ifelse(
      history_data$has_active,
      paste0(history_data$term, ": ", history_data$enrolled),
      paste0(history_data$term, ": C")
    )
  } else {
    labels <- paste0(history_data$term, ": ", history_data$enrolled)
  }

  return(paste(labels, collapse = " \u2192 "))
}