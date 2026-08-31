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

  only_waitlisted <- get_true_waitlisted_rows(filtered_students, sections)
  waitlist_counts <- summarize_waitlist_courses(only_waitlisted) %>%
    arrange(campus, subject_course, desc(count))


  # Return course groups for waitlisted students who are not also registered.
  message("[waitlist.R] Returning ", nrow(waitlist_counts), " waitlisted course groups...")
  return(waitlist_counts)
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


# HOW WAITLIST COUNTING WORKS (plain English)
#
# 1. Start with every class-list row that matches the user's filters.
# 2. Find students with a waitlist (WL) row for a course.
# 3. Remove anyone who also has a registered (RE/RS/RR) row for that same
#    campus, term, part of term, and course. This leaves "true demand": students
#    who are waiting for a seat and do not already hold one in that course scope.
# 4. Count each remaining student only once within each displayed group. Multiple
#    waitlist rows or sections therefore cannot count the same student twice.
# 5. Build all three tables from this same true-demand population:
#      - Course Overview groups by course (plus campus/term/part of term).
#      - By Program adds the student's major/program.
#      - By Classification adds the student's academic classification.
#    Because the same filtered students feed every table, their counts describe
#    the same population; only the grouping changes.

#' Select true waitlist-demand rows
#'
#' Keeps waitlisted students who do not also hold a registered row for the same
#' campus, term, part of term (when present), and course. Registration codes are
#' preferred; the display status is supported for backward-compatible callers.
#' @param df Student enrollment rows containing waitlist and registered statuses.
#' @param sections Optional sections table used when course titles are absent.
#' @keywords internal
get_true_waitlisted_rows <- function(df, sections = NULL) {
  df <- ensure_course_title(df, sections) %>% ungroup()

  if ("registration_status_code" %in% names(df)) {
    is_waitlisted <- df$registration_status_code %in% STATUS_WAITLIST
    is_registered <- df$registration_status_code %in% STATUS_REGISTERED
  } else if ("registration_status" %in% names(df)) {
    is_waitlisted <- df$registration_status == "Wait Listed"
    is_registered <- grepl("Registered", df$registration_status, ignore.case = TRUE)
  } else {
    stop("[waitlist.R] input needs registration_status_code or registration_status")
  }

  has_college   <- "college" %in% names(df)
  has_part_term <- "part_term" %in% names(df)
  identity_keys <- c("campus", if (has_college) "college", "term",
                     if (has_part_term) "part_term",
                     "subject_course", "course_title", "student_id")

  registered_keys <- df[is_registered, , drop = FALSE] %>%
    distinct(across(all_of(identity_keys)))

  df[is_waitlisted, , drop = FALSE] %>%
    anti_join(registered_keys, by = identity_keys)
}


#' Summarize true waitlist demand by course
#'
#' Counts distinct students for each course overview row while carrying optional
#' college and part-of-term dimensions when the input provides them.
#' @param waitlisted_students True waitlist-demand rows.
#' @return One row per course grouping with a distinct-student `count`.
#' @keywords internal
summarize_waitlist_courses <- function(waitlisted_students) {
  has_college   <- "college" %in% names(waitlisted_students)
  has_part_term <- "part_term" %in% names(waitlisted_students)
  group_cols <- c("campus", if (has_college) "college", "term",
                  if (has_part_term) "part_term",
                  "subject_course", "course_title")

  waitlisted_students %>%
    ungroup() %>%
    distinct(across(all_of(c(group_cols, "student_id")))) %>%
    count(across(all_of(group_cols)), name = "count")
}


#' Summarize true waitlist demand by demographic groups
#'
#' Focused count-only alternative to the full demographic enrollment summary.
#' @param waitlisted_students True waitlist-demand rows.
#' @param group_cols Columns defining the requested demographic breakdown.
#' @return One row per group with a distinct-student `count`.
#' @keywords internal
summarize_waitlist_groups <- function(waitlisted_students, group_cols) {
  waitlisted_students %>%
    ungroup() %>%
    distinct(across(all_of(c(group_cols, "student_id")))) %>%
    count(across(all_of(group_cols)), name = "count")
}


#' Scope the enrollment base to waitlist course keys
#'
#' Keeps every historical term for the course keys present in a waitlist result,
#' while dropping unrelated courses before census-history aggregation begins.
#' @param enrl_base Precomputed course-term enrollment rows.
#' @param count_df Waitlist course-overview rows.
#' @return A list containing scoped `data` and the shared `match_keys`.
#' @keywords internal
scope_waitlist_enrollment_base <- function(enrl_base, count_df) {
  match_keys <- Reduce(intersect, list(
    c("campus", "college", "subject_course", "part_term"),
    names(count_df), names(enrl_base)))

  history_scope <- count_df %>%
    ungroup() %>%
    distinct(across(all_of(match_keys)))
  scoped_base <- enrl_base %>%
    ungroup() %>%
    semi_join(history_scope, by = match_keys) %>%
    select(all_of(unique(c(match_keys, "term", "term_type", "registered", "dr_late"))))

  list(data = scoped_base, match_keys = match_keys)
}


#' Attach per-course census-enrollment context to the waitlist course overview
#'
#' Enriches the waitlist count table with each course's current-term census
#' enrollment, its historical average census enrollment (same term type, viewed
#' term excluded), the count of reference terms behind that average, and the
#' same-term-type census series used to draw a sparkline in the UI. This reference
#' can include later terms when reviewing an older target; Regstats instead uses
#' a strictly prior baseline. The count uses registered plus late drops (see
#' \code{\link{add_census_enrl}}), not a frozen census or the mixed-source
#' reconstruction used by Regstats saturation.
#'
#' Enrollment history comes from the precomputed \code{cedar_cl_enrls_base} table
#' (built in global.R) when it is in scope; outside the running app (tests,
#' standalone scripts) it is recomputed via \code{\link{calc_cl_enrls}}, scoped to just the courses in
#' the overview so the fallback stays cheap.
#'
#' @param count_df Waitlist course-overview table (one row per campus/college/
#'   term/part_term/subject_course) from \code{\link{get_unique_waitlisted}}.
#' @param students Student enrollment rows, used to recompute enrollment history
#'   when no precomputed base table is available.
#' @return \code{count_df} with added columns \code{census_enrl} (current-term
#'   census enrollment), \code{census_enrl_mean} (historical average, viewed term
#'   excluded), \code{n_hist_terms} (reference terms behind the average), and the
#'   \code{trend_hist} / \code{trend_terms} list-columns the module renders as a
#'   sparkline. Returned unchanged when no enrollment source is available.
#' @keywords internal
attach_enrollment_history <- function(count_df, students) {
  if (is.null(count_df) || nrow(count_df) == 0) return(count_df)

  # Prefer the app's precomputed base; fall back to a scoped recompute so tests
  # and standalone-script callers (no global base) still get enrollment context.
  enrl_base <- if (exists("cedar_cl_enrls_base", inherits = TRUE))
    get("cedar_cl_enrls_base", inherits = TRUE) else NULL

  if (is.null(enrl_base)) {
    raw_match_keys <- intersect(
      c("campus", "college", "subject_course", "part_term"),
      intersect(names(count_df), names(students)))
    raw_scope <- count_df %>%
      ungroup() %>%
      distinct(across(all_of(raw_match_keys)))
    scoped <- students %>%
      ungroup() %>%
      semi_join(raw_scope, by = raw_match_keys)
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

  if (!all(c("registered", "dr_late", "term", "term_type") %in% names(enrl_base)))
    return(count_df)

  # The app-wide enrollment base contains every course and term. Restrict it to
  # the course keys in this waitlist result before any mutate/group/summarize
  # work; all historical terms for those keys remain available for the trend.
  history_input <- scope_waitlist_enrollment_base(enrl_base, count_df)
  match_keys <- history_input$match_keys
  enrl_base <- add_census_enrl(history_input$data)

  # Current-term census enrollment (and the row's term_type, taken from the base so
  # it matches how the baselines are grouped). Summed across any finer dimensions
  # (e.g. part_term when the overview lacks it) so each course×term is one figure.
  cur <- enrl_base %>%
    group_by(across(all_of(c(match_keys, "term", "term_type")))) %>%
    summarize(census_enrl = sum(census_enrl, na.rm = TRUE), .groups = "drop")
  count_df <- count_df %>%
    left_join(cur, by = c(match_keys, "term"))

  # Historical census baselines: mean over prior same-term-type offerings (viewed
  # terms excluded), prior-term count, and the full series for the sparkline. One
  # row per course×term_type; many overview rows can share a baseline.
  baselines <- calc_census_enrl_baselines(
    enrl_base, target_terms = unique(count_df$term),
    keys = c(match_keys, "term_type"))
  count_df <- count_df %>%
    left_join(baselines, by = c(match_keys, "term_type")) %>%
    rename(census_enrl_mean = census_mean,
           trend_hist       = census_hist,
           trend_terms      = census_hist_terms)

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
#'   student_classification, subject_course, course_title, level, and
#'   registration_status_code (or the backward-compatible registration_status).
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
#'   \item Counts distinct true-waitlist students twice:
#'     \itemize{
#'       \item Once grouped by major (major)
#'       \item Once grouped by classification (student_classification)
#'     }
#'   \item Computes unique course-level waitlist counts
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
#' \code{\link{summarize_waitlist_groups}} for grouping logic,
#' \code{\link{get_unique_waitlisted}} for unique student counts
#'
#' @export
inspect_waitlist <- function(students, opt, sections = NULL) {

  message("[waitlist.R] Welcome to inspect_waitlist!")

  message("[waitlist.R] Filtering students from params...")
  filtered_students <- filter_class_list(students, opt)

  filtered_students <- ensure_course_title(filtered_students, sections)

  # Keep only true demand: students waitlisted for a course who do not also hold
  # a registered row for that same course scope.
  waitlisted_students <- get_true_waitlisted_rows(filtered_students)

  # Create empty list for waitlist data
  waitlist_data <- list()

  major_groups <- c("campus", "college", "term", "term_type",
                    "major_code", "subject_course", "course_title", "level")
  waitlist_data[["majors"]] <- summarize_waitlist_groups(
    waitlisted_students, major_groups) %>%
    select(-college, -level, -term_type) %>%
    arrange(campus, desc(count))

  classification_groups <- c("campus", "college", "term", "term_type",
                             "student_classification", "subject_course", "course_title", "level")
  waitlist_data[["classifications"]] <- summarize_waitlist_groups(
    waitlisted_students, classification_groups) %>%
    select(-college, -level, -term_type) %>%
    arrange(campus, desc(count))

  waitlist_data[["count"]] <- summarize_waitlist_courses(waitlisted_students) %>%
    arrange(campus, subject_course, desc(count))

  # Enrich the course overview with section-supply metrics so the waitlist count
  # reads as demand against capacity: how many sections currently run, their
  # average operating size, and how many additional sections would clear the
  # waitlist at that size. Supply is scoped to the same campus/term/course
  # combinations that produced the waitlist demand (waitlisted_students is
  # already true-demand-only and opt-filtered above).
  if (!is.null(sections) && nrow(waitlist_data[["count"]]) > 0) {
    scope <- waitlisted_students %>%
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
