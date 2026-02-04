# =============================================================================
# HELPER FUNCTIONS - Pure, testable functions for grade analysis
# =============================================================================

#' Count Grades by Grouping Columns
#'
#' Summarizes grade counts from student data by specified grouping columns.
#' This is a pure function that operates on pre-filtered data.
#'
#' @param students Data frame with final_grade column plus grouping columns
#' @param group_cols Character vector of column names to group by
#'
#' @return Data frame with grade counts grouped by specified columns:
#'   \describe{
#'     \item{...group_cols...}{All specified grouping columns}
#'     \item{final_grade}{The grade value}
#'     \item{count}{Number of students with this grade}
#'   }
#'
#' @examples
#' \dontrun{
#' group_cols <- c("term", "subject_course", "instructor_last_name")
#' counts <- count_grades(filtered_students, group_cols)
#' }
count_grades <- function(students, group_cols) {
  if (nrow(students) == 0) {
    message("[gradebook.R] count_grades: empty input, returning empty data frame")
    return(data.frame())
  }

  students %>%
    group_by(across(all_of(c(group_cols, "final_grade")))) %>%
    summarize(count = n(), .groups = "keep")
}


#' Categorize Grades into Passed, Failed, and Dropped
#'
#' Takes grade counts and separates them into passed, failed, early dropped,
#' and late dropped categories. This is a pure function for testability.
#'
#' @param grade_counts Data frame from count_grades() with final_grade and count columns
#' @param group_cols Character vector of column names used for grouping
#' @param passing_grades Character vector of grades considered passing (e.g., c("A", "B", "C"))
#'
#' @return Data frame with columns:
#'   \describe{
#'     \item{...group_cols...}{All specified grouping columns}
#'     \item{passed}{Count of students with passing grades}
#'     \item{failed}{Count of students with failing grades (excludes early drops)}
#'     \item{early_dropped}{Count of students who dropped early (DR status, shown as "Drop")}
#'     \item{late_dropped}{Count of students who withdrew late (W grade)}
#'   }
#'
#' @details
#' Grade categorization:
#' - Passed: grades in passing_grades list
#' - Failed: grades NOT in passing_grades AND NOT "Drop" (includes W, F, D, etc.)
#' - Early dropped: "Drop" grade (from DR registration status)
#' - Late dropped: "W" grade specifically
#'
#' @examples
#' \dontrun{
#' categorized <- categorize_grades(grade_counts, group_cols, passing_grades)
#' }
categorize_grades <- function(grade_counts, group_cols, passing_grades) {
  if (nrow(grade_counts) == 0) {
    message("[gradebook.R] categorize_grades: empty input, returning empty data frame")
    return(data.frame())
  }

  # Passed grades

  passed <- grade_counts %>%
    filter(final_grade %in% passing_grades) %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(passed = sum(count), .groups = "keep")

  # Failed grades (not passing, not early drop)
  failed <- grade_counts %>%
    filter(final_grade != "Drop" & !final_grade %in% passing_grades) %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(failed = sum(count), .groups = "keep")

  # Late drops (W grade specifically)
  late_drops <- grade_counts %>%
    filter(final_grade == "W") %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(late_dropped = sum(count), .groups = "keep")

  # Early drops (DR status, shown as "Drop" grade)
  early_drops <- grade_counts %>%
    filter(final_grade == "Drop") %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(early_dropped = sum(count), .groups = "keep")

  # Merge all categories
  result <- merge(passed, failed, all = TRUE)
  result <- merge(result, late_drops, all = TRUE)
  result <- merge(result, early_drops, all = TRUE)

  # Replace NAs with 0s
  result %>% mutate_if(is.numeric, ~replace_na(., 0))
}


#' Calculate DFW Percentage
#'
#' Adds dfw_pct column to categorized grade data.
#' Formula: dfw_pct = failed / (passed + failed) * 100
#'
#' @param categorized Data frame from categorize_grades() with passed and failed columns
#'
#' @return Same data frame with added "dfw_pct" column
#'
#' @details
#' The DFW calculation excludes early drops (DR status) since those students
#' are not counted in enrollment totals.
#'
#' @examples
#' \dontrun{
#' dfw_summary <- calculate_dfw(categorized)
#' }
calculate_dfw <- function(categorized) {
  if (nrow(categorized) == 0) {
    message("[gradebook.R] calculate_dfw: empty input, returning empty data frame")
    return(categorized)
  }

  categorized %>%
    mutate(dfw_pct = round(failed / (passed + failed) * 100, digits = 2))
}


# =============================================================================
# DATA PREPARATION HELPERS
# =============================================================================

#' Prepare Student Data for Grade Analysis
#'
#' Filters and preprocesses student enrollment data for DFW calculations.
#' This is a pure function that handles all preprocessing steps.
#'
#' @param students Data frame from cedar_students table
#' @param opt Options list for filtering (passed to filter_class_list)
#'
#' @return Data frame of prepared students ready for grade counting, or
#'   empty data frame if no students match filters
#'
#' @details
#' Preprocessing steps:
#' \enumerate{
#'   \item Filter students using filter_class_list() with provided options
#'   \item Restrict to Fall 2019 or later (term >= 201980, after Gen Ed implementation)
#'   \item Convert DR (Drop) registration status to "Drop" final grade
#'   \item Remove duplicate student records per section (by student_id, campus, college, crn)
#'   \item Merge with grades_to_points lookup table for grade point values
#' }
#'
#' @examples
#' \dontrun{
#' opt <- list(course = "MATH 1430", term = 202510)
#' prepared <- prepare_students_for_grading(cedar_students, opt)
#' }
prepare_students_for_grading <- function(students, opt) {
  message("[gradebook.R] Received students data: ", nrow(students), " rows")
  message("[gradebook.R] Options: ", toString(opt))

  # Filter students from opt params (usually course and term OR dept for dept reports)
  filtered_students <- filter_class_list(students, opt)

  # If no data after filtering, return empty
  if (nrow(filtered_students) == 0) {
    message("[gradebook.R] No students found after filtering, returning empty data frame")
    return(data.frame())
  }

  message("[gradebook.R] Only using data since 2019 (after Gen Ed implementation).")
  filtered_students <- filtered_students %>% filter(term >= 201980)

  if (nrow(filtered_students) == 0) {
    message("[gradebook.R] No students found after term filter, returning empty data frame")
    return(data.frame())
  }

  message("[gradebook.R] Setting final_grade to 'Drop' if registration status code is 'DR'.")
  filtered_students <- filtered_students %>%
    mutate(final_grade = ifelse(registration_status_code == "DR", "Drop", final_grade))

  # Get distinct IDs in each course (use CRN since same student can retake a course)
  message("[gradebook.R] Finding distinct rows based on student_id, campus, college, crn...")
  filtered_students <- filtered_students %>%
    distinct(student_id, campus, college, crn, .keep_all = TRUE)

  # Merge grade points from letter grade received
  # grades_to_points is defined in lists/grades.R
  message("[gradebook.R] Merging grades_to_points table with grade data...")
  message("[gradebook.R] Rows before merge: ", nrow(filtered_students))
  filtered_students <- merge(filtered_students, grades_to_points,
                             by.x = "final_grade", by.y = "grade", all.x = TRUE)
  message("[gradebook.R] Rows after merge: ", nrow(filtered_students))

  return(filtered_students)
}


#' Merge Faculty Job Category Data with Grade Counts
#'
#' Adds instructor job category (TT/NTT) from HR data to grade counts.
#'
#' @param grade_counts Data frame with grade counts including instructor_id and term
#' @param cedar_faculty Data frame from cedar_faculty table with job_category
#'
#' @return grade_counts with job_category column added (if merge successful),
#'   or original grade_counts if no matches found (non-A&S units)
#'
#' @examples
#' \dontrun{
#' grade_counts_with_job <- merge_faculty_data(grade_counts, cedar_faculty)
#' }
merge_faculty_data <- function(grade_counts, cedar_faculty) {
  # Prepare cedar_faculty data for merge (select only needed columns)
  fac_small <- cedar_faculty %>%
    distinct(instructor_id, term, .keep_all = TRUE) %>%
    select(instructor_id, term, job_category)
  message("[gradebook.R] Rows in fac_small: ", nrow(fac_small))

  message("[gradebook.R] Merging faculty job category data by instructor ID AND term...")
  merged <- grade_counts %>%
    merge(fac_small, by.x = c("instructor_id", "term"), by.y = c("instructor_id", "term"))

  # Test if trying to merge faculty data squashes student data
  if (nrow(merged) == 0) {
    message("[gradebook.R] Merging grade_counts with cedar_faculty resulted in 0 rows. Probably a non A&S unit.")
    return(grade_counts)
  } else {
    message("[gradebook.R] Merging grade_counts with cedar_faculty yielded rows: ", nrow(merged))
    return(merged)
  }
}


#' Build Aggregation List from DFW Summary
#'
#' Creates multiple aggregated views of grade data at different granularities.
#'
#' @param dfw_summary Data frame with DFW statistics
#' @param grade_counts Data frame with grade counts for section counting
#'
#' @return Named list with aggregated tables:
#'   \describe{
#'     \item{course_inst_avg}{Averages by course and instructor (across all terms)}
#'     \item{inst_type}{Averages by course, term, and instructor type (job_category)}
#'     \item{course_term}{Averages by course and term}
#'     \item{course_avg}{Overall course averages (across all terms)}
#'     \item{course_avg_by_term}{Course averages for each individual term}
#'   }
#'
#' @examples
#' \dontrun{
#' aggregations <- build_aggregation_list(dfw_summary, grade_counts)
#' }
build_aggregation_list <- function(dfw_summary, grade_counts) {
  grades_list <- list()
  opt <- list()

  # Get averages by course, campus, college, and instructor but NOT TERM (mean across terms)
  opt[["group_cols"]] <- c("campus", "college", "instructor_last_name", "subject_course")
  course_inst_avg <- aggregate_grades(dfw_summary, opt)

  # Add section count per instructor
  # Count unique term/course combinations per instructor (each term counted separately)
  instructor_section_counts <- grade_counts %>%
    distinct(campus, instructor_last_name, term, subject_course) %>%
    group_by(campus, instructor_last_name) %>%
    summarize(sections_taught = n(), .groups = "drop")
  message("[gradebook.R] Rows in instructor_section_counts: ", nrow(instructor_section_counts))

  # Merge the section counts back into course_inst_avg
  grades_list[["course_inst_avg"]] <- course_inst_avg %>%
    ungroup() %>%
    left_join(instructor_section_counts, by = c("campus", "instructor_last_name"))
  message("[gradebook.R] Rows in course_inst_avg: ", nrow(grades_list[["course_inst_avg"]]))

  # Get course averages by instructor type
  opt[["group_cols"]] <- c("campus", "college", "term", "subject_course", "job_category")
  grades_list[["inst_type"]] <- aggregate_grades(dfw_summary, opt)
  message("[gradebook.R] Rows in inst_type: ", nrow(grades_list[["inst_type"]]))

  # Get course averages by campus and college
  opt[["group_cols"]] <- c("campus", "college", "term", "subject_course")
  grades_list[["course_term"]] <- aggregate_grades(dfw_summary, opt)
  message("[gradebook.R] Rows in course_term: ", nrow(grades_list[["course_term"]]))

  # Get course averages (all terms)
  opt[["group_cols"]] <- c("campus", "college", "subject_course")
  grades_list[["course_avg"]] <- aggregate_grades(dfw_summary, opt)
  message("[gradebook.R] Rows in course_avg: ", nrow(grades_list[["course_avg"]]))

  # Get course averages (for each term)
  opt[["group_cols"]] <- c("campus", "college", "subject_course", "term")
  grades_list[["course_avg_by_term"]] <- aggregate_grades(dfw_summary, opt)
  message("[gradebook.R] Rows in course_avg_by_term: ", nrow(grades_list[["course_avg_by_term"]]))

  return(grades_list)
}


# =============================================================================
# AGGREGATION FUNCTION
# =============================================================================

#' Aggregate Grade Data by Grouping Columns
#'
#' Aggregates DFW (Drop/Fail/Withdraw) summary data by specified grouping columns,
#' calculating totals for passed, failed, and dropped students, plus overall DFW percentage.
#'
#' @param dfw_summary Data frame with columns: passed, failed, early_dropped, late_dropped
#'   plus any columns specified in opt$group_cols
#' @param opt Options list containing:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of column names to group by
#'   }
#'
#' @return Data frame aggregated by group_cols with columns:
#'   \describe{
#'     \item{passed}{Total passed students}
#'     \item{failed}{Total failed students}
#'     \item{early_dropped}{Total early drops (DR status)}
#'     \item{late_dropped}{Total late drops (W grade)}
#'     \item{DFW \%}{Percentage calculated as failed/(passed+failed)*100}
#'   }
#'   Plus all grouping columns.
#'
#' @details
#' This function validates that all requested group_cols exist in the data before
#' aggregating. Missing columns are automatically removed with a warning. The DFW
#' percentage calculation excludes early drops (DR) since those students are not
#' counted in enrollment totals.
#'
#' @seealso \code{\link{get_grades}} for the main gradebook workflow
aggregate_grades <- function(dfw_summary, opt) {
  # Check if dfw_summary is empty
  if (nrow(dfw_summary) == 0) {
    message("[gradebook.R] dfw_summary is empty, returning empty summary dataframe")
    return(dfw_summary)
  }
  
  group_cols <- opt[["group_cols"]]
  group_cols <- convert_param_to_list(group_cols)
  group_cols <- as.character(group_cols)
  
  # Verify all group_cols exist in dfw_summary
  missing_cols <- setdiff(group_cols, names(dfw_summary))
  if (length(missing_cols) > 0) {
    message("[gradebook.R] WARNING: group_cols contains columns not in dfw_summary: ", paste(missing_cols, collapse = ", "))
    message("[gradebook.R] Available columns: ", paste(names(dfw_summary), collapse = ", "))
    # Remove missing columns from group_cols
    group_cols <- intersect(group_cols, names(dfw_summary))
    message("[gradebook.R] Using only available columns: ", paste(group_cols, collapse = ", "))
  }
  
  summary <- dfw_summary %>%
    group_by(across(all_of(group_cols))) %>% 
    summarize(passed = sum(passed), failed = sum(failed), early_dropped = sum(early_dropped), late_dropped = sum(late_dropped), .groups="keep") 
  
  # add dfw column with summarized data
  # failed already includes all non-passing grades (including Drop from late drops)
  summary <- summary %>%
    mutate(dfw_pct = round(failed/(passed + failed)*100,digits=2))
  
  return (summary)
}


#' Get Grade Data and Calculate DFW Statistics
#'
#' Main controller function for grade analysis. Filters student enrollment data,
#' calculates DFW (Drop/Fail/Withdraw) statistics, merges with CEDAR faculty data for
#' instructor categorization, and produces multiple aggregated views of grade data.
#'
#' @param students Data frame from cedar_students table with columns:
#'   student_id, campus, college, term, crn, subject_course, final_grade,
#'   registration_status_code, instructor_last_name, instructor_id
#' @param cedar_faculty Data frame from cedar_faculty table with columns:
#'   instructor_id, term, job_category
#' @param opt Options list for filtering and grouping:
#'   \itemize{
#'     \item \code{course} - Course identifier(s) to filter by
#'     \item \code{dept} - Department code to filter by
#'     \item \code{term} - Term code(s) to filter by
#'     \item Other filter options supported by \code{filter_class_list()}
#'   }
#'
#' @return Named list with grade data at various aggregation levels:
#'   \describe{
#'     \item{counts}{Grade counts by campus, college, term, course, instructor, grade}
#'     \item{dfw_summary}{DFW summary with passed, failed, early_dropped, late_dropped counts}
#'     \item{course_inst_avg}{Averages by course and instructor (across all terms)}
#'     \item{inst_type}{Averages by course, term, and instructor type (job_cat)}
#'     \item{course_term}{Averages by course and term}
#'     \item{course_avg}{Overall course averages (across all terms)}
#'     \item{course_avg_by_term}{Course averages for each individual term}
#'   }
#'
#' @details
#' The function performs the following workflow:
#' \enumerate{
#'   \item Filters students using \code{filter_class_list()} with provided options
#'   \item Restricts to Fall 2019 or later (after Gen Ed implementation: term >= 201980)
#'   \item Converts DR (Drop) registration status to "Drop" final grade
#'   \item Removes duplicate student records per section
#'   \item Merges with grades_to_points lookup table
#'   \item Summarizes grade counts by campus, college, term, course, instructor
#'   \item Merges with HR data to add instructor job category (job_cat)
#'   \item Separates grades into passed, failed, early drops, and late drops
#'   \item Calculates DFW percentage: failed/(passed+failed)*100
#'   \item Produces multiple aggregated views using \code{aggregate_grades()}
#'   \item Adds section counts per instructor
#' }
#'
#' **Important**: DFW % calculation excludes early drops (DR status) since those
#' students are not counted in enrollment totals.
#'
#' Passing grades are defined in includes/lists.R (typically A+, A, A-, B+, B, B-, C+, C, C-, D+, D, D-, S, CR)
#'
#' @examples
#' \dontrun{
#' # Get grades for a specific course
#' opt <- list(course = "MATH 1430", term = 202510)
#' grades <- get_grades(cedar_students, cedar_faculty, opt)
#'
#' # View DFW summary
#' head(grades$dfw_summary)
#'
#' # Get grades for a department
#' opt <- list(dept = "HIST")
#' dept_grades <- get_grades(cedar_students, cedar_faculty, opt)
#' }
#'
#' @seealso
#' \code{\link{aggregate_grades}} for aggregation logic,
#' \code{\link{plot_grades_for_course_report}} for visualization,
#' \code{\link{get_grades_for_dept_report}} for department-specific analysis
#'
#' @export
get_grades <- function(students, cedar_faculty, opt) {
  message("[gradebook.R] Welcome to get_grades!")
  message("[gradebook.R] Received cedar_faculty data: ", nrow(cedar_faculty), " rows")


  # 1. Prepare student data (filter, clean, merge grades_to_points)
  prepared_students <- prepare_students_for_grading(students, opt)
  if (nrow(prepared_students) == 0) {
    message("[gradebook.R] No students after preparation, returning empty list")
    return(list())
  }

  # 2. Count grades by standard grouping columns
  group_cols <- c("campus", "college", "term", "subject_course",
                  "instructor_last_name", "instructor_id")
  message("[gradebook.R] Producing summary of grades grouped by: ", paste(group_cols, collapse = ", "))
  grade_counts <- count_grades(prepared_students, group_cols)
  message("[gradebook.R] Total grade records in grade_counts: ", sum(grade_counts$count))

  # 3. Merge faculty data (adds job_category if available)
  grade_counts <- merge_faculty_data(grade_counts, cedar_faculty)

  # 4. Update group_cols for categorization (remove instructor_id, add job_category if present)
  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  if ("job_category" %in% names(grade_counts)) {
    group_cols <- c(group_cols, "job_category")
  }
  message("[gradebook.R] group_cols for categorization: ", paste(group_cols, collapse = ", "))

  # 5. Categorize grades and calculate DFW
  message("[gradebook.R] Categorizing grades using helper functions...")
  message("[gradebook.R] passing grades are: ", paste(passing_grades, collapse = ", "))
  categorized <- categorize_grades(grade_counts, group_cols, passing_grades)
  dfw_summary <- calculate_dfw(categorized)

  # 6. Build all aggregations
  grades_list <- build_aggregation_list(dfw_summary, grade_counts)
  grades_list[["counts"]] <- grade_counts
  grades_list[["dfw_summary"]] <- dfw_summary

  message("[gradebook.R] returning grades_list...")
  return(grades_list)
}



# generate grade plots for course report
plot_grades_for_course_report <- function(grades, opt) {

  # studio testing...
  #grades <- grades_list
  
  message("[gradebook.R] Welcome to plot_grades_for_course_report!")

  # Check if grades data is available
  if (is.null(grades) || length(grades) == 0) {
    message("[gradebook] No grades data available for plotting.")
    return(NULL)
  } else {
    message("[gradebook.R] Grades data contains ", length(grades), " tables for plotting. Objects in grades object: ", paste(names(grades), collapse = ", "))
  }

  # Create a list to hold the plots
  plots <- list()

# get dfw_summary by course and term 
  dfw_summary_by_course <- grades[["course"]]
  
  # get dfw_summary averages across terms
  dfw_summary_by_course_avg <- grades[["course_avg"]]
  
  # get instructor-level averages across terms
  instructor_data <- grades[["course_inst_avg"]] %>%
    filter(!is.na(instructor_last_name) & instructor_last_name != "")

  # Create consistent factor levels for both datasets
  course_levels <- dfw_summary_by_course_avg %>%
    arrange(subject_course) %>%
    pull(subject_course) %>%
    unique()

  # Prepare bar data (CEDAR pattern)
  bar_data <- dfw_summary_by_course_avg %>%
    mutate(subject_course = factor(subject_course, levels = course_levels))

  # Prepare instructor point data - use same structure as bar data for consistent positioning
  point_data <- instructor_data %>%
    mutate(subject_course = factor(subject_course, levels = course_levels)) %>%
    group_by(subject_course, campus) %>%
    mutate(instructor_index = row_number() - 1) %>%  # Index for stacking multiple instructors
    ungroup()

  # Define consistent dodge width
  dodge_width <- 0.8
  
  message("[gradebook.R] Plotting DFW summary plot...")
  dfw_summary_plot <- bar_data %>%
    ggplot(aes(y=subject_course, x=dfw_pct, fill=campus,
               text = paste("Course:", subject_course,
                           "<br>Campus:", campus,
                           "<br>DFW %:", dfw_pct))) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(stat="identity", position=position_dodge(width=dodge_width), alpha=0.7) +
    geom_point(data = point_data,
               aes(x=dfw_pct,
                   y=subject_course,  # Use the factor directly - let position_dodge handle positioning
                   color=campus,
                   text = paste("Instructor:", instructor_last_name,
                               "<br>Course:", subject_course,
                               "<br>Campus:", campus,
                               "<br>DFW %:", dfw_pct,
                               "<br>Sections Taught:", sections_taught)),
               position=position_jitterdodge(dodge.width=dodge_width, jitter.height=0.15, jitter.width=0),
               size=2, alpha=0.8, inherit.aes = FALSE) +
    ylab("Course") + xlab("mean DFW %")  +
    labs(caption = "Bars show course averages; dots show individual instructor averages")
  
  # Convert to plotly for interactivity and store in plots list
  plots[["dfw_summary_plot"]] <- ggplotly(dfw_summary_plot, tooltip = "text")
  plots$dfw_summary_plot

  # line plot of course averages by term and combine with bar plot
  message("[gradebook.R] Plotting DFW by term...")
  term_data <- grades[["course_avg_by_term"]]
  if (!is.null(term_data) && nrow(term_data) > 0) {
    term_levels <- sort(unique(term_data$term))
    term_plot <- term_data %>%
      mutate(
        AcadTerm = factor(term, levels = term_levels),
        subject_course = as.character(subject_course)
      ) %>%
      ggplot(aes(x = AcadTerm, y = dfw_pct, group = subject_course, color = campus,
                 text = paste("Course:", subject_course,
                              "<br>Term:", term,
                              "<br>DFW %:", dfw_pct))) +
      geom_line() +
      geom_point() +
      labs(x = "Academic Period", y = "DFW %", title = "Course averages by term") +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")

    plots[["dfw_by_term_plot"]] <- ggplotly(term_plot, tooltip = "text")
    #plots[["dfw_by_term_plot"]]
  }


  # plot of DFW rates by intructor type over
  message("[gradebook.R] Plotting DFW by instructor type...")
  term_data <- grades[["inst_type"]]
  if (!is.null(term_data) && nrow(term_data) > 0) {
    term_levels <- sort(unique(term_data$term))
    term_plot <- term_data %>%
      mutate(
        AcadTerm = factor(term, levels = term_levels),
        subject_course = as.character(subject_course)
      ) %>%
      ggplot(aes(x = AcadTerm, y = dfw_pct, fill = `job_category`,
                 text = paste("Course:", subject_course,
                              "<br>Term:", term,
                              "<br>DFW %:", dfw_pct))) +
      #geom_line() +
      #geom_point() +
      geom_bar(stat = "identity", position = "dodge") +
      facet_wrap(~campus, ncol = 1) +
      labs(x = "Academic Period", y = "DFW %", title = "Course averages by instructor type") +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")

    plots[["dfw_by_inst_type_plot"]] <- ggplotly(term_plot, tooltip = "text")
    #plots[["dfw_by_inst_type_plot"]]
  }


  message("[gradebook.R] Returning ", length(plots), " grade plots for course report.")  
  return(plots)
}



# this is specifically for creating dept report outputs using d_params
# it does additional filtering for lower division courses if available
get_grades_for_dept_report <- function(students, cedar_faculty, opt, d_params) {

  # studio testing set up
  #opt <- list()
  #opt[["dept"]] <- "MATH"
  #students <- load_students()
  #cedar_faculty <- load_datafile("cedar_faculty")

  # for plotting
  myopt <- opt
  myopt[["dept"]] <- d_params$dept_code


  # limit to ABQ campus and online until we have better plotting across campuses
  message("[gradebook.R] limiting to ABQ and EA campus for plotting...")
  myopt[["course_campus"]] <- c("ABQ","EA")

  message("[gradebook.R] limiting to lower division courses for plotting...")
  myopt[["level"]] <- "lower"

  # get various grade tables for the specified department
  grades <- get_grades(students, cedar_faculty, myopt)
  
  # handle case of empty grades object
  if (is.null(grades) || length(grades) == 0) {
    message("[gradebook.R] No grades data available after filtering for plotting. Returning d_params unchanged.")
    return(d_params)
  } else {
    message("[gradebook.R] Grades data contains ", length(grades), " tables for plotting. Objects in grades object: ", paste(names(grades), collapse = ", "))
  }

  # get dfw_summary by course and term 
  dfw_summary_by_course <- grades[["course"]]

  message("[gradebook.R] adding dfw_summary_by_course to d_params...")
  d_params$tables[["grades_summary_for_ld"]] <- dfw_summary_by_course

  # get dfw_summary averages across terms
  dfw_summary_by_course_avg <- grades[["course_avg"]]
  
  # get instructor-level averages across terms
  instructor_data <- grades[["course_inst_avg"]] %>%
    filter(!is.na(instructor_last_name) & instructor_last_name != "")

  # Create consistent factor levels for both datasets
  course_levels <- dfw_summary_by_course_avg %>%
    arrange(subject_course) %>%
    pull(subject_course) %>%
    unique()

  dfw_summary_for_ld_plot <- dfw_summary_by_course_avg %>%
    mutate(subject_course = factor(subject_course, levels = course_levels)) %>%
    ggplot(aes(y=subject_course, x=dfw_pct, fill=campus,
               text = paste("Course:", subject_course,
                           "<br>Campus:", campus,
                           "<br>DFW %:", dfw_pct))) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(stat="identity", position=position_dodge(), alpha=0.7) +
    geom_point(data = instructor_data %>%
                 mutate(subject_course = factor(subject_course, levels = course_levels)),
               aes(x=dfw_pct, y=subject_course, color=campus,
                   text = paste("Instructor:", instructor_last_name,
                               "<br>Course:", subject_course,
                               "<br>Campus:", campus,
                               "<br>DFW %:", dfw_pct,
                               "<br>Sections Taught:", sections_taught)),
               position=position_jitter(height=0.2, width=0),
               size=2, alpha=0.8) +
    ylab("Course") + xlab("mean DFW %")  +
    labs(caption = "Bars show course averages; dots show individual instructor averages")
  
  # Convert to plotly for interactivity
  dfw_summary_for_ld_plot <- ggplotly(dfw_summary_for_ld_plot, tooltip = "text")
  
  dfw_summary_for_ld_plot
  


  message("[gradebook] adding grades_summary_for_ld_abq_ea_plot to d_params...")
  d_params$plots[["grades_summary_for_ld_abq_ea_plot"]] <- dfw_summary_for_ld_plot 

  
  message("[gradebook] returning d_params with new plot(s) and table(s)...")
  return(d_params)
}

