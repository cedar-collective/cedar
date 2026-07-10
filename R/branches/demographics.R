#' Summarize Student Demographics
#'
#' Flexible demographic summary function that groups students by any specified columns
#' (majors, classifications, or other demographic fields) and calculates enrollment
#' counts, means across terms, and percentages of course enrollment. This provides
#' insight into "who" is taking courses over time.
#'
#' Lives in branches/ because it is consumed by multiple cones
#' (course-demographics.R and waitlist.R).
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
#' @seealso
#' \code{\link{get_course_demographics}} for the main entry point,
#' \code{\link{calc_cl_enrls}} for enrollment counts
#'
#' @export
summarize_student_demographics <- function(filtered_students, opt) {
  message("[demographics.R] Welcome to summarize_student_demographics!")

  group_cols <- opt[["group_cols"]]

  if (is.null(group_cols)) {
    message("[demographics.R] No group_cols specified. Using defaults.")
    group_cols <- c("campus", "college", "term", "term_type",
                    "major_code", "student_classification", "subject_course", "course_title", "level")
  } else {
    message("[demographics.R] Using provided group_cols.")
    group_cols <- convert_param_to_list(group_cols)
    group_cols <- as.character(group_cols)
  }

  message("[demographics.R] group_cols: ", paste(group_cols, collapse = ", "))

  # Group and count distinct students
  summary <- filtered_students %>%
    group_by_at(group_cols) %>%
    distinct(student_id, .keep_all = TRUE) %>%
    summarize(.groups = "keep", count = n())

  # Regroup without "term" to calculate means across terms
  group_cols <- group_cols[-which(group_cols %in% c("term"))]

  summary <- summary %>%
    group_by_at(group_cols) %>%
    mutate(mean = round(mean(count), digits = 1))

  # Count course enrollments and percentages
  reg_summary <- calc_cl_enrls(filtered_students)

  crse_enrollment <- reg_summary %>%
    ungroup() %>%
    select(c(campus, college, subject_course, term, registered, registered_mean))

  merge_sum_enrl <- merge(summary, crse_enrollment, by = c("campus", "college",
                                                           "term", "subject_course"))
  merge_sum_enrl <- merge_sum_enrl %>%
    group_by(campus, college, term, subject_course) %>%
    mutate(term_pct      = round(count / registered * 100, digits = 1)) %>%
    mutate(term_type_pct = round(mean / registered_mean  * 100, digits = 1)) %>%
    arrange(campus, college, term, subject_course, desc(term_pct))

  message("[demographics.R] Returning student demographic summary with ", nrow(merge_sum_enrl), " rows...")
  return(merge_sum_enrl)
}

#' @describeIn summarize_student_demographics Deprecated name for backward compatibility
#' @export
summarize_classifications <- function(filtered_students, opt) {
  warning("[demographics.R] summarize_classifications() is deprecated. Use summarize_student_demographics() instead.")
  summarize_student_demographics(filtered_students, opt)
}
