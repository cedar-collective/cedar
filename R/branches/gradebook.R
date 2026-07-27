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
  count_attempt_grades(students, group_cols)
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

  # Failed grades (not passing, not early drop, not late drop/W)
  failed <- grade_counts %>%
    filter(final_grade != "Drop" & final_grade != "W" & !final_grade %in% passing_grades) %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(failed = sum(count), .groups = "keep")

  # Late drops: W grade (includes DG/DW status students whose grade was set to "W" upstream)
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
#' Formula: dfw_pct = (failed + late_dropped) / (passed + failed + late_dropped) * 100
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
    mutate(dfw_pct = round((failed + late_dropped) / (passed + failed + late_dropped) * 100, digits = 2))
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
#' @param opt Options list for filtering (passed to filter_class_list).
#'   Also supports:
#'   \itemize{
#'     \item \code{cohort_ids} - Character vector of student IDs. If provided,
#'       analysis is restricted to these students after all other filters are
#'       applied. Use with cohorts built by \code{build_cohort()} in cohort.R.
#'   }
#'
#' @return Data frame of prepared students ready for grade counting, or
#'   empty data frame if no students match filters
#'
#' @details
#' Preprocessing steps:
#' \enumerate{
#'   \item Filter students using filter_class_list() with provided options
#'   \item If opt$population_ids is provided, restrict to those students
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
  message("[gradebook.R] prepare_students_for_grading delegates to prepare_course_attempts().")
  prepare_course_attempts(students, opt)
}


#' Merge Faculty Job Category Data with Grade Counts
#'
#' Adds instructor job category (TT/NTT) from HR data to grade counts.
#'
#' @param grade_counts Data frame with grade counts including instructor_id and term
#' @param cedar_faculty Data frame from cedar_faculty table with job_category
#'
#' @return grade_counts with job_category column added
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
    merge(fac_small, by.x = c("instructor_id", "term"), by.y = c("instructor_id", "term"), all.x = TRUE)

  if (nrow(merged) == 0) {
    stop(
      "\n❌ merge_faculty_data: merging grade_counts with cedar_faculty produced 0 rows.",
      "\n   Ensure cedar_faculty contains data for the same instructors and terms as grade_counts.",
      "\n   cedar_faculty only contains CAS departments — do not call add_instructor_type() for non-CAS units.\n"
    )
  }

  message("[gradebook.R] Merging grade_counts with cedar_faculty yielded rows: ", nrow(merged))
  return(merged)
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

  # Add section count per instructor per course.
  # Count unique terms an instructor taught this specific course — each term = one section.
  # subject_course must be in both the group_by and the join key so that an instructor
  # who teaches multiple courses (e.g., Prior teaching HIST 101, 201, and 490) gets a
  # separate, correct count for each course rather than their total across all courses.
  distinct_terms <- grade_counts %>%
    ungroup() %>%
    distinct(campus, instructor_last_name, subject_course, term)
  message("[gradebook.R] distinct instructor/course/term rows: ", nrow(distinct_terms))

  instructor_section_counts <- distinct_terms %>%
    group_by(campus, instructor_last_name, subject_course) %>%
    summarize(sections_taught = n(), .groups = "drop")
  message("[gradebook.R] Rows in instructor_section_counts: ", nrow(instructor_section_counts))
  if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
    message("[gradebook.R] instructor_section_counts:\n",
            paste(capture.output(print(as.data.frame(instructor_section_counts))), collapse = "\n"))
  }

  # Merge the section counts back into course_inst_avg
  grades_list[["course_inst_avg"]] <- course_inst_avg %>%
    ungroup() %>%
    left_join(instructor_section_counts, by = c("campus", "instructor_last_name", "subject_course"))
  message("[gradebook.R] Rows in course_inst_avg: ", nrow(grades_list[["course_inst_avg"]]))

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
# INSTRUCTOR TYPE ENRICHMENT
# =============================================================================

#' Add Instructor Type to Grade Data
#'
#' Enriches a grades list (from get_grades()) with instructor job category (TT/NTT)
#' from HR data, and adds the inst_type aggregation table grouped by job_category.
#'
#' @param grades Named list returned by get_grades()
#' @param cedar_faculty Data frame from cedar_faculty table with instructor_id, term, job_category
#'
#' @return grades list with job_category added to counts/dfw_summary and inst_type table added
#'
#' @details
#' cedar_faculty only contains CAS departments. For non-CAS units (e.g. Nursing),
#' this function will stop() since no faculty records will match. Only call this
#' function when faculty data is available for the departments being analyzed.
#'
#' @examples
#' \dontrun{
#' grades <- get_grades(cedar_students, opt)
#' grades <- add_instructor_type(grades, cedar_faculty)
#' }
add_instructor_type <- function(grades, cedar_faculty) {
  message("[gradebook.R] add_instructor_type: adding job_category from cedar_faculty")
  message("[gradebook.R] Received cedar_faculty data: ", nrow(cedar_faculty), " rows")

  grade_counts <- grades[["counts"]]

  # Merge faculty job category into grade counts
  grade_counts <- merge_faculty_data(grade_counts, cedar_faculty)

  # Recategorize with job_category as a grouping column
  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name", "job_category")
  categorized <- categorize_grades(grade_counts, group_cols, passing_grades)
  dfw_summary <- calculate_dfw(categorized)

  # Build inst_type aggregation
  opt_inst <- list(group_cols = c("campus", "college", "term", "subject_course", "job_category"))
  inst_type <- aggregate_grades(dfw_summary, opt_inst)
  message("[gradebook.R] Rows in inst_type: ", nrow(inst_type))

  # Update grades list
  grades[["counts"]]      <- grade_counts
  grades[["dfw_summary"]] <- dfw_summary
  grades[["inst_type"]]   <- inst_type

  return(grades)
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
  
  summary <- summary %>%
    mutate(dfw_pct = round((failed + late_dropped) / (passed + failed + late_dropped) * 100, digits = 2))
  
  return (summary)
}


#' Get Legacy Gradebook Report Bundle
#'
#' Legacy/report facade for grade analysis. New cones should use
#' \code{get_course_outcome_rates()} for DFW/outcome metrics or
#' \code{get_grade_distribution()} for letter-grade distributions unless they
#' explicitly need this full report bundle.
#'
#' This function preserves the existing report contract while delegating row-level
#' cleanup to \code{prepare_course_attempts()}.
#'
#' @param students Data frame from cedar_students table with columns:
#'   student_id, campus, college, term, crn, subject_course, final_grade,
#'   registration_status_code, instructor_last_name, instructor_id
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
#'     \item{course_term}{Averages by course and term}
#'     \item{course_avg}{Overall course averages (across all terms)}
#'     \item{course_avg_by_term}{Course averages for each individual term}
#'   }
#'   Call \code{add_instructor_type(grades, cedar_faculty)} on the result to add
#'   \code{inst_type} (TT/NTT breakdown) when faculty data is available.
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
#'   \item Separates grades into passed, failed, early drops, and late drops
#'   \item Calculates DFW percentage: failed/(passed+failed)*100
#'   \item Produces multiple aggregated views using \code{aggregate_grades()}
#'   \item Adds section counts per instructor
#' }
#'
#' To add instructor type (TT/NTT) breakdowns, call \code{add_instructor_type(grades, cedar_faculty)}
#' on the result. This is a separate step because faculty data is only available for CAS departments.
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
#' grades <- get_grades(cedar_students, opt)
#'
#' # View DFW summary
#' head(grades$dfw_summary)
#'
#' # Get grades for a department with instructor type breakdown
#' opt <- list(dept = "HIST")
#' grades <- get_grades(cedar_students, opt)
#' grades <- add_instructor_type(grades, cedar_faculty)  # CAS departments only
#' }
#'
#' @seealso
#' \code{\link{aggregate_grades}} for aggregation logic,
#' \code{\link{plot_grades_for_course_report}} for visualization
#'
#' @export
get_grades <- function(students, opt) {
  message("[gradebook.R] Welcome to get_grades!")

  # 1. Prepare student data (filter, clean, merge grades_to_points)
  prepared_students <- prepare_students_for_grading(students, opt)
  if (nrow(prepared_students) == 0) {
    message("[gradebook.R] No students after preparation, returning empty list")
    return(list())
  }

  # Diagnostic: show how many unique courses we found data for
  unique_courses <- prepared_students %>%
    distinct(campus, college, subject_course) %>%
    nrow()
  message("[gradebook.R] Found grade data for ", unique_courses, " unique course/campus/college combinations")

  # 2. Count grades by standard grouping columns
  group_cols <- c("campus", "college", "term", "subject_course",
                  "instructor_last_name", "instructor_id")
  message("[gradebook.R] Producing summary of grades grouped by: ", paste(group_cols, collapse = ", "))
  grade_counts <- count_grades(prepared_students, group_cols)
  message("[gradebook.R] Total grade records in grade_counts: ", sum(grade_counts$count))

  # 3. Group columns for categorization (use add_instructor_type() for TT/NTT breakdown)
  group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
  message("[gradebook.R] group_cols for categorization: ", paste(group_cols, collapse = ", "))

  # 4. Categorize grades and calculate DFW
  message("[gradebook.R] Categorizing grades using helper functions...")
  message("[gradebook.R] passing grades are: ", paste(passing_grades, collapse = ", "))
  categorized <- categorize_grades(grade_counts, group_cols, passing_grades)
  dfw_summary <- calculate_dfw(categorized)

  # 5. Build all aggregations
  grades_list <- build_aggregation_list(dfw_summary, grade_counts)
  grades_list[["counts"]] <- grade_counts
  grades_list[["dfw_summary"]] <- dfw_summary

  # Diagnostic: show what's in course_avg (this is what seatfinder uses)
  if (!is.null(grades_list[["course_avg"]])) {
    message("[gradebook.R] course_avg table has ", nrow(grades_list[["course_avg"]]), " rows")
    if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
      message("[gradebook.R] Courses in course_avg:")
      course_avg_courses <- grades_list[["course_avg"]] %>%
        distinct(campus, college, subject_course) %>%
        arrange(campus, college, subject_course)
      message(paste(capture.output(print(course_avg_courses)), collapse = "\n"))
    }
  }

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

  include_instructor_points <- opt[["include_instructor_points"]] %||% FALSE

  # Create a list to hold the plots
  plots <- list()

# get dfw_summary by course and term 
  dfw_summary_by_course <- grades[["course"]]
  
  # get dfw_summary averages across terms
  dfw_summary_by_course_avg <- grades[["course_avg"]]
  
  include_instructor_points <- isTRUE(opt$include_instructor_points)

  # get instructor-level averages across terms
  instructor_data <- if (include_instructor_points) {
    grades[["course_inst_avg"]] %>%
      filter(!is.na(instructor_last_name) & instructor_last_name != "")
  } else {
    tibble()
  }

  # Create consistent factor levels for both datasets
  course_levels <- dfw_summary_by_course_avg %>%
    arrange(subject_course) %>%
    pull(subject_course) %>%
    unique()

  # Prepare bar data (CEDAR pattern)
  bar_data <- dfw_summary_by_course_avg %>%
    mutate(subject_course = factor(subject_course, levels = course_levels))

  # Prepare instructor point data - use same structure as bar data for consistent positioning.
  # Only built when instructor points are requested; otherwise instructor_data is an empty
  # tibble() with no columns and the subject_course mutate below would error.
  point_data <- if (include_instructor_points) {
    instructor_data %>%
      mutate(subject_course = factor(subject_course, levels = course_levels)) %>%
      group_by(subject_course, campus) %>%
      mutate(instructor_index = row_number() - 1) %>%
      ungroup()
  } else {
    tibble()
  }

  # Apply campus filter if specified in opt
  campus_filter <- opt[["course_campus"]]
  if (!is.null(campus_filter) && length(campus_filter) > 0) {
    bar_data <- bar_data %>% filter(campus %in% campus_filter)
    if (include_instructor_points) {
      point_data <- point_data %>% filter(campus %in% campus_filter)
    }
  }

  message("[gradebook.R] Plotting DFW summary plot...")
  p_summary <- plot_ly()

  # Layer 1: campus average as a vertical tick mark (the "reference line" per course).
  # legendgroup ties the tick and its dots together so legend clicks hide both.
  for (camp in sort(unique(bar_data$campus))) {
    bd <- filter(bar_data, campus == camp)
    p_summary <- add_markers(p_summary, data = bd,
                x    = ~dfw_pct, y = ~subject_course,
                color       = ~campus,
                legendgroup = ~campus,
                name        = camp,
                marker      = list(size = 20, symbol = "line-ns-open",
                                   line = list(width = 3)),
                hovertemplate = "Campus avg: %{x:.1f}%%<br>Course: %{y}<br>Campus: %{fullData.name}<extra></extra>")
  }

  if (isTRUE(include_instructor_points)) {
    # Layer 2: individual instructor rates as smaller filled circles.
    for (camp in sort(unique(point_data$campus))) {
      pd <- filter(point_data, campus == camp) %>%
        mutate(.hover = paste0(instructor_last_name, " (",
                               sections_taught, " term",
                               ifelse(sections_taught == 1, "", "s"), ")"))
      p_summary <- add_markers(p_summary, data = pd,
                  x    = ~dfw_pct, y = ~subject_course,
                  color       = ~campus,
                  legendgroup = ~campus,
                  showlegend  = FALSE,
                  marker      = list(size = 8, opacity = 0.75, symbol = "circle"),
                  customdata  = ~.hover,
                  hovertemplate = paste0("Instructor: %{customdata}<br>Course: %{y}",
                                         "<br>Campus: %{fullData.name}",
                                         "<br>DFW %%: %{x:.1f}<extra></extra>"))
    }
  }

  summary_note <- if (isTRUE(include_instructor_points)) {
    "| marks campus course average; dots show individual instructor rates"
  } else {
    "| marks campus course average"
  }

  plots[["dfw_summary_plot"]] <- p_summary %>%
    layout(xaxis   = list(title = "DFW %"),
           yaxis   = list(title = ""),
           legend  = list(orientation = "h", x = 0, y = -0.15),
           annotations = list(list(
             text = summary_note,
             showarrow = FALSE, xref = "paper", yref = "paper",
             x = 0, y = -0.22, xanchor = "left", font = list(size = 10, color = "grey")
           )))

  # line plot of DFW rate by term, colored by campus
  message("[gradebook.R] Plotting DFW by term...")
  term_data <- grades[["course_avg_by_term"]]
  if (!is.null(campus_filter) && length(campus_filter) > 0 && !is.null(term_data)) {
    term_data <- term_data %>% filter(campus %in% campus_filter)
  }
  if (!is.null(term_data) && nrow(term_data) > 0) {
    td <- term_data %>%
      arrange(term) %>%
      mutate(term_label = fmt_term(term))
    campuses <- unique(td$campus)
    p <- plot_ly()
    for (camp in campuses) {
      cd <- td %>% filter(campus == camp)
      p <- p %>% add_trace(
        data = cd,
        x = ~term_label, y = ~dfw_pct,
        name = camp,
        type = "scatter", mode = "lines+markers",
        hovertemplate = paste0("Term: %{x}<br>Campus: ", camp, "<br>DFW %%: %{y:.1f}<extra></extra>")
      )
    }
    plots[["dfw_by_term_plot"]] <- p %>% layout(
      xaxis  = list(title = "Term", tickangle = -45,
                    categoryorder = "array",
                    categoryarray = unique(td$term_label)),
      yaxis  = list(title = "DFW %"),
      legend = list(orientation = "h", x = 0, y = -0.25)
    )
  }


  # plot of DFW rates by instructor type over time
  message("[gradebook.R] Plotting DFW by instructor type...")
  term_data <- grades[["inst_type"]]
  if (!is.null(campus_filter) && length(campus_filter) > 0 && !is.null(term_data)) {
    term_data <- term_data %>% filter(campus %in% campus_filter)
  }
  if (!is.null(term_data) && nrow(term_data) > 0) {
    term_levels <- sort(unique(term_data$term))
    campuses   <- unique(term_data$campus)
    sub_plots  <- lapply(seq_along(campuses), function(i) {
      camp <- campuses[[i]]
      plot_ly(
        term_data %>%
          filter(campus == camp) %>%
          mutate(term = factor(term, levels = term_levels),
                 subject_course = as.character(subject_course)),
        x = ~term, y = ~dfw_pct, color = ~job_category,
        type          = "bar",
        showlegend    = (i == 1),
        legendgroup   = ~job_category,
        hovertemplate = "Course: %{customdata}<br>Term: %{x}<br>DFW %%: %{y:.1f}<extra>%{fullData.name}</extra>",
        customdata    = ~subject_course
      ) %>% layout(
        barmode = "group",
        annotations = list(list(text = camp, showarrow = FALSE,
                                xref = "paper", yref = "paper",
                                x = 0.5, y = 1.05, font = list(size = 11))),
        xaxis = list(tickangle = -45)
      )
    })
    plots[["dfw_by_inst_type_plot"]] <- subplot(
      sub_plots, nrows = length(campuses), shareX = FALSE, shareY = FALSE,
      titleX = TRUE, titleY = TRUE, margin = 0.08
    ) %>% layout(
      title  = list(text = "Course averages by instructor type", x = 0),
      yaxis  = list(title = "DFW %"),
      legend = list(orientation = "h", x = 0, y = -0.15)
    )
    #plots[["dfw_by_inst_type_plot"]]
  }


  message("[gradebook.R] Returning ", length(plots), " grade plots for course report.")  
  return(plots)
}



get_grades_for_dept_report <- function(students, cedar_faculty, dept_code, opt = list()) {
  stop(
    "[gradebook.R] get_grades_for_dept_report() is retired with the legacy ",
    "Dept Report DFW/SFR tab. Use get_grades() plus ",
    "plot_grades_for_course_report() for maintained DFW analysis."
  )
}
