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
#' @param sections Optional cedar_sections table; only needed if filtered_students
#'   lacks a course_title column (titles are joined by term/subject_course)
#'
#' @return Data frame with columns:
#'   \itemize{
#'     \item \code{campus} - Campus code
#'     \item \code{college} - College code (only when the input carries a college column)
#'     \item \code{term} - Term code
#'     \item \code{part_term} - Part of term (only when the input carries a part_term column)
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
get_unique_waitlisted <- function(filtered_students, opt, sections = NULL) {

  message("[waitlist.R] Welcome to get_unique_waitlisted!")

  # Ensure course_title is available; join from sections if missing
  filtered_students <- ensure_course_title(filtered_students, sections)

  # Carry college and part_term through when present (real app path via
  # inspect_waitlist); the direct-caller unit tests pass fixtures without those
  # columns, so keep them optional. term is grouped on so each term reads as its
  # own row in the course overview.
  has_college   <- "college" %in% names(filtered_students)
  has_part_term <- "part_term" %in% names(filtered_students)
  select_cols <- c("campus", if (has_college) "college", "term",
                   if (has_part_term) "part_term",
                   "subject_course", "course_title", "student_id")
  group_cols  <- c("campus", if (has_college) "college", "term",
                   if (has_part_term) "part_term",
                   "subject_course", "course_title")

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
    group_by(across(all_of(group_cols))) %>%
    summarize(count = n(), .groups = "drop") %>%
    arrange(campus, subject_course, desc(count))


  # Return waitlisted IDs not also registered
  message("[waitlist.R] Returning ", nrow(only_waitlisted), " waitlisted students not registered...")
  return(only_waitlisted)
}

#' Ensure course_title column is present for waitlist summaries
#'
#' cedar_students normally carries course_title; if the input lacks it, titles
#' are joined from the sections table, which must then be supplied explicitly.
#' @param df Student enrollment rows.
#' @param sections cedar_sections table; only required when df has no course_title.
#' @keywords internal
ensure_course_title <- function(df, sections = NULL) {
  if ("course_title" %in% names(df)) {
    return(df)
  }

  if (is.null(sections)) {
    stop("[waitlist.R] input has no course_title column and no sections table was supplied; ",
         "pass cedar_sections so titles can be joined")
  }

  title_source <- sections %>%
    select(term, subject_course, course_title) %>%
    distinct()

  df %>% left_join(title_source, by = c("term", "subject_course"))
}


#' Attach per-course enrollment context to the waitlist course overview
#'
#' Enriches the waitlist count table with each course's current-term enrollment,
#' its historical average enrollment (same term type, excluding the viewed term),
#' and the same-term-type enrollment series used to draw a sparkline in the UI.
#' This mirrors the enrollment context shown on the regstats bumps/saturation
#' tables so a waitlist count reads against how full the course usually runs.
#'
#' Enrollment history comes from the precomputed \code{cedar_cl_enrls_base} table
#' (built in global.R) when it is in scope; outside the running app (tests, CLI)
#' it is recomputed via \code{\link{calc_cl_enrls}}, scoped to just the courses in
#' the overview so the fallback stays cheap.
#'
#' @param count_df Waitlist course-overview table (one row per campus/college/
#'   term/part_term/subject_course) from \code{\link{get_unique_waitlisted}}.
#' @param students Student enrollment rows, used to recompute enrollment history
#'   when no precomputed base table is available.
#' @return \code{count_df} with added columns \code{registered} (current-term
#'   enrollment), \code{registered_mean} (historical average, viewed term
#'   excluded), and the \code{trend_hist} / \code{trend_terms} list-columns the
#'   module renders as a sparkline. Returned unchanged when no enrollment source
#'   is available.
#' @keywords internal
attach_enrollment_history <- function(count_df, students) {
  if (is.null(count_df) || nrow(count_df) == 0) return(count_df)

  # Prefer the app's precomputed base; fall back to a scoped recompute so tests
  # and CLI callers (no global base) still get enrollment context.
  enrl_base <- if (exists("cedar_cl_enrls_base", inherits = TRUE))
    get("cedar_cl_enrls_base", inherits = TRUE) else NULL

  if (is.null(enrl_base)) {
    scoped <- students %>% filter(subject_course %in% unique(count_df$subject_course))
    if (nrow(scoped) == 0) return(count_df)
    by_pt <- "part_term" %in% names(scoped)
    # tryCatch is intentional: missing enrollment context must not sink the
    # waitlist inspection — a failed recompute just leaves the extra columns off.
    enrl_base <- tryCatch(
      calc_cl_enrls(scoped, by_part_term = by_pt),
      error = function(e) {
        message("[waitlist.R] Skipping enrollment context: ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(enrl_base)) return(count_df)
  }

  if (!all(c("registered", "term", "term_type") %in% names(enrl_base))) return(count_df)

  # Match on the keys shared by both frames. part_term is included only when both
  # carry it, so a half-term section's history isn't diluted by the full-term one.
  match_keys <- Reduce(intersect, list(
    c("campus", "college", "subject_course", "part_term"),
    names(count_df), names(enrl_base)))

  # Collapse the base to the overview's granularity (summing across any finer
  # dimensions, e.g. part_term when the overview lacks it) so each course×term
  # resolves to exactly one enrollment figure and the joins can't fan out.
  base_agg <- enrl_base %>%
    group_by(across(all_of(c(match_keys, "term", "term_type")))) %>%
    summarize(registered = sum(registered, na.rm = TRUE), .groups = "drop")

  # Current-term enrollment (and the row's term_type, taken from the base so it
  # matches how the series is grouped below).
  count_df <- count_df %>%
    left_join(base_agg, by = c(match_keys, "term"))

  # Same-term-type enrollment series (oldest→newest) for the sparkline: one list
  # per course×term_type. Many overview rows can share a single series.
  series <- base_agg %>%
    arrange(term) %>%
    group_by(across(all_of(c(match_keys, "term_type")))) %>%
    summarize(trend_hist = list(registered), trend_terms = list(term), .groups = "drop")
  count_df <- count_df %>%
    left_join(series, by = c(match_keys, "term_type"))

  # Historical average excludes the viewed term (matches the regstats "Hist Avg").
  count_df$registered_mean <- mapply(function(th, tt, tm) {
    if (is.null(th) || length(th) == 0) return(NA_real_)
    keep <- tt != tm
    if (!any(keep)) return(NA_real_)
    round(mean(th[keep], na.rm = TRUE), 1)
  }, count_df$trend_hist, count_df$trend_terms, count_df$term)

  count_df
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
#' @param sections Optional cedar_sections table; only needed if students
#'   lacks a course_title column (titles are joined by term/subject_course)
#'
#' @return Named list with three elements:
#'   \itemize{
#'     \item \code{majors} - Data frame summarizing waitlist by major/program.
#'       Columns: campus, term, subject_course, course_title, major, count
#'     \item \code{classifications} - Data frame summarizing waitlist by student level.
#'       Columns: campus, term, subject_course, course_title, student_classification, count
#'     \item \code{count} - Data frame of unique waitlisted students (see
#'       \code{\link{get_unique_waitlisted}}), enriched (when \code{sections} is
#'       supplied) with \code{n_sections} (active sections offered), \code{avg_size}
#'       (mean enrolled per section), and \code{sections_needed} (additional
#'       sections to clear the waitlist at the average size).
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
inspect_waitlist <- function(students, opt, sections = NULL) {

  message("[waitlist.R] Welcome to inspect_waitlist!")

  message("[waitlist.R] Filtering students from params...")
  filtered_students <- filter_class_list(students, opt)

  filtered_students <- ensure_course_title(filtered_students, sections)

  # Get only waitlisted students
  filtered_students <- filtered_students %>% filter(registration_status == "Wait Listed")

  # Set groups in case multiple courses are selected
  filtered_students <- filtered_students %>%
    group_by(campus, college, term, term_type,
           major_code, subject_course, course_title, level)

  # Create empty list for waitlist data
  waitlist_data <- list()

  # Set group_cols for Major
  opt[["group_cols"]] <- c("campus", "college", "term", "term_type",
                          "major_code", "subject_course", "course_title", "level")

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

  waitlist_data[["count"]] <- get_unique_waitlisted(filtered_students, opt, sections)

  # Enrich the course overview with section-supply metrics so the waitlist count
  # reads as demand against capacity: how many sections currently run, their
  # average operating size, and how many additional sections would clear the
  # waitlist at that size. Supply is scoped to the same campus/term/course
  # combinations that produced the waitlist demand (filtered_students is already
  # Wait-Listed-only and opt-filtered above).
  if (!is.null(sections) && nrow(waitlist_data[["count"]]) > 0) {
    scope <- filtered_students %>%
      ungroup() %>%
      distinct(campus, term, subject_course)

    # Scope supply to the same campus/term/course as the demand. The count table
    # is now one row per term, so keep section stats at term granularity too and
    # join on term as well, otherwise cross-term sections would be double-counted.
    section_stats <- sections %>%
      semi_join(scope, by = c("campus", "term", "subject_course")) %>%
      # Match get_section_size_lookup(): use actual enrolled (not capacity), and
      # drop crosslist partners whose enrolled duplicates the primary section.
      filter((is.na(crosslist_role) | crosslist_role != "partner"), enrolled > 0) %>%
      group_by(campus, term, subject_course) %>%
      summarize(
        n_sections = n_distinct(section_id),
        avg_size   = mean(enrolled, na.rm = TRUE),
        .groups    = "drop"
      )

    waitlist_data[["count"]] <- waitlist_data[["count"]] %>%
      left_join(section_stats, by = c("campus", "term", "subject_course")) %>%
      mutate(
        sections_needed = if_else(!is.na(avg_size) & avg_size > 0,
                                  as.integer(ceiling(count / avg_size)),
                                  NA_integer_),
        avg_size        = round(avg_size, 1)
      )
  }

  # Add enrollment context (current enrollment, historical average, trend series)
  # so each waitlist row reads against how full the course usually runs.
  waitlist_data[["count"]] <- attach_enrollment_history(waitlist_data[["count"]], students)

  message("[waitlist.R] Returning waitlist data...")

  return(waitlist_data)
}
