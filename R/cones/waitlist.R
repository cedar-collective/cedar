#' Get Unique Waitlisted Students Not Registered
#'
#' Identifies students who are waitlisted for a course but not registered, providing
#' counts by campus and course. This helps identify "true" waitlist demand by excluding
#' students who are registered for another section.
#'
#' @param filtered_students Data frame of student enrollments from cedar_students table,
#'   already filtered by opt parameters. Must include columns:
#'   campus, term, subject_course, course_title, student_id, registration_status
#' @param opt Options list (currently unused but kept for consistency)
#'
#' @return Data frame with columns:
#'   \itemize{
#'     \item \code{campus} - Campus code
#'     \item \code{subject_course} - Course identifier
#'     \item \code{count} - Number of unique students waitlisted only (not registered)
#'   }
#'   Sorted by campus, subject_course, and descending count.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Identifies unique waitlisted students (registration_status = "Wait Listed")
#'   \item Identifies registered students (registration_status contains "Registered")
#'   \item Uses set difference to find students waitlisted but not registered
#'   \item Groups by campus and course, counting unique students
#'   \item Sorts results for easy interpretation
#' }
#'
#' This is useful for understanding "real" waitlist demand - students who want the
#' course but couldn't get in, as opposed to those who are registered elsewhere.
#'
#' @examples
#' \dontrun{
#' # Get waitlist counts for MATH courses
#' opt <- list(subject = "MATH", term = "202510")
#' filtered <- filter_class_list(cedar_students, opt)
#' waitlist_counts <- get_unique_waitlisted(filtered, opt)
#' }
#'
#' @seealso \code{\link{inspect_waitlist}} for comprehensive waitlist analysis
get_unique_waitlisted <- function(filtered_students, opt) {

  message("[waitlist.R] Welcome to get_unique_waitlisted!")

  # Ensure course_title is available; join cedar_sections if missing
  filtered_students <- ensure_course_title(filtered_students)

  select_cols <- c("campus", "term", "subject_course", "course_title", "student_id")

  # Get waitlisted student IDs
  waitlisted <- filtered_students %>%
    filter(registration_status == "Wait Listed") %>%
    select(all_of(select_cols)) %>%
    unique()

  # Get registered student IDs
  registered <- filtered_students %>%
    filter(grepl("Registered", registration_status, ignore.case = TRUE)) %>%
    select(all_of(select_cols)) %>%
    unique()


  only_waitlisted <- setdiff(waitlisted, registered)

  only_waitlisted <- only_waitlisted %>%
    group_by(campus, subject_course) %>%
    summarize(count = n(), .groups = "drop") %>%
    arrange(campus, subject_course, desc(count))


  # Return waitlisted IDs not also registered
  message("[waitlist.R] Returning ", nrow(only_waitlisted), " waitlisted students not registered...")
  return(only_waitlisted)
}

# Minimal helper to guarantee course_title is present for waitlist summaries.
# Attempts to join cedar_sections by term/subject_course; falls back to
# subject_course if no title is available.
ensure_course_title <- function(df) {
  if ("course_title" %in% names(df)) {
    return(df)
  }

  title_source <- NULL
  if (exists("cedar_sections", inherits = TRUE)) {
    title_source <- tryCatch({
      cedar_sections %>%
        select(term, subject_course, course_title) %>%
        distinct()
    }, error = function(e) NULL)
  }

  if (!is.null(title_source)) {
    df <- df %>% left_join(title_source, by = c("term", "subject_course"))
  }

  if (!"course_title" %in% names(df)) {
    df$course_title <- df$subject_course
  }

  df
}


#' Inspect Waitlist by Major and Classification
#'
#' Comprehensive waitlist analysis that breaks down waitlisted students by their
#' major and classification. This provides insight into which student populations
#' are being waitlisted and helps with enrollment planning and advising.
#'
#' @param students Data frame of student enrollments from cedar_students table.
#'   Must include columns: campus, college, term, term_type, major,
#'   student_classification, subject_course, course_title, level, registration_status
#' @param opt Options list for filtering:
#'   \itemize{
#'     \item \code{course} - Course identifier(s) (e.g., "MATH 1430")
#'     \item \code{term} - Term code(s) (e.g., 202510)
#'     \item \code{subject} - Subject code(s) (e.g., "MATH")
#'     \item Other filtering options supported by \code{filter_class_list()}
#'   }
#'
#' @return Named list with three elements:
#'   \itemize{
#'     \item \code{majors} - Data frame summarizing waitlist by major/program.
#'       Columns: campus, term, subject_course, course_title, major, count
#'     \item \code{classifications} - Data frame summarizing waitlist by student level.
#'       Columns: campus, term, subject_course, course_title, student_classification, count
#'     \item \code{count} - Data frame of unique waitlisted students (see \code{\link{get_unique_waitlisted}})
#'   }
#'
#' @details
#' This function performs the following steps:
#' \enumerate{
#'   \item Filters students using \code{filter_class_list()} with provided options
#'   \item Restricts to waitlisted students only (registration_status = "Wait Listed")
#'   \item Groups data by campus, college, term, course, and demographics
#'   \item Calls \code{summarize_student_demographics()} twice:
#'     \itemize{
#'       \item Once grouped by major (major)
#'       \item Once grouped by classification (student_classification)
#'     }
#'   \item Computes unique waitlisted counts via \code{get_unique_waitlisted()}
#'   \item Returns cleaned summaries with unnecessary columns removed
#' }
#'
#' The returned data is useful for:
#' \itemize{
#'   \item Understanding which majors have highest waitlist demand
#'   \item Identifying whether freshmen vs upperclassmen are being waitlisted
#'   \item Planning section additions or seat reservations
#'   \item Advising students about course availability
#' }
#'
#' @examples
#' \dontrun{
#' # Analyze waitlist for specific course
#' opt <- list(course = "MATH 1430", term = 202510)
#' waitlist_analysis <- inspect_waitlist(cedar_students, opt)
#'
#' # View by major
#' head(waitlist_analysis$majors)
#'
#' # View by classification
#' head(waitlist_analysis$classifications)
#'
#' # Analyze all BIOL courses in a term
#' opt <- list(subject = "BIOL", term = "202510")
#' bio_waitlist <- inspect_waitlist(cedar_students, opt)
#' }
#'
#' @seealso
#' \code{\link{filter_class_list}} for filtering options,
#' \code{\link{summarize_student_demographics}} for grouping logic,
#' \code{\link{get_unique_waitlisted}} for unique student counts
#'
#' @export
inspect_waitlist <- function(students, opt) {

  message("[waitlist.R] Welcome to inspect_waitlist!")

  message("[waitlist.R] Filtering students from params...")
  filtered_students <- filter_class_list(students, opt)

  filtered_students <- ensure_course_title(filtered_students)

  # Get only waitlisted students
  filtered_students <- filtered_students %>% filter(registration_status == "Wait Listed")

  # Set groups in case multiple courses are selected
  filtered_students <- filtered_students %>%
    group_by(campus, college, term, term_type,
           major, subject_course, course_title, level)

  # Create empty list for waitlist data
  waitlist_data <- list()

  # Set group_cols for Major
  opt[["group_cols"]] <- c("campus", "college", "term", "term_type",
                          "major", "subject_course", "course_title", "level")

  waitlist_data[["majors"]] <- summarize_student_demographics(filtered_students, opt) %>%
    ungroup() %>%
    select(-c(college, level, term_type, mean, registered, registered_mean, term_pct, term_type_pct)) %>%
    arrange(campus, desc(count))


  # Set group_cols for Classification
  opt[["group_cols"]] <- c("campus", "college", "term", "term_type",
                          "student_classification", "subject_course", "course_title", "level")

  waitlist_data[["classifications"]] <- summarize_student_demographics(filtered_students, opt) %>%
    ungroup() %>%
    select(-c(college, level, term_type, mean, registered, registered_mean, term_pct, term_type_pct)) %>%
    arrange(campus, desc(count))

  waitlist_data[["count"]] <- get_unique_waitlisted(filtered_students, opt)

  message("[waitlist.R] Returning waitlist data...")

  return(waitlist_data)
}
