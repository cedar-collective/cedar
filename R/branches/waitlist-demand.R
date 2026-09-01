# Shared class-list waitlist-demand calculations.
#
# Waitlists, Regstats, and the Department Dashboard all use these helpers so a
# displayed waitlist count has one meaning across the app: distinct WL students
# who do not also hold a registered row for the same reporting group.

#' Ensure course title is present for waitlist matching and summaries
#'
#' Course title is part of the waitlist reporting grain because topics courses
#' can reuse a subject/course number for different offerings. The class list
#' normally carries it; callers may supply sections for title enrichment when it
#' does not.
#' @param df Student enrollment rows.
#' @param sections Optional cedar_sections table used for title enrichment.
#' @return `df` with a `course_title` column.
#' @keywords internal
ensure_waitlist_course_title <- function(df, sections = NULL) {
  has_title <- "course_title" %in% names(df)
  if (has_title) {
    existing_title <- trimws(as.character(df$course_title))
    if (is.null(sections) || all(!is.na(existing_title) & nzchar(existing_title))) {
      return(df)
    }
  }

  if (is.null(sections)) {
    stop("[waitlist-demand.R] input has no course_title column and no sections table was supplied; ",
         "pass cedar_sections so titles can be joined")
  }

  optional_title_keys <- intersect(c("campus", "college", "part_term"),
                                   intersect(names(df), names(sections)))
  optional_title_keys <- optional_title_keys[vapply(optional_title_keys, function(key) {
    any(!is.na(df[[key]]) & nzchar(as.character(df[[key]])))
  }, logical(1))]
  title_keys <- c(optional_title_keys, "term", "subject_course")
  if (!all(c("term", "subject_course") %in% title_keys)) {
    stop("[waitlist-demand.R] cannot join course titles without term and subject_course")
  }

  title_source <- sections %>%
    dplyr::select(dplyr::all_of(title_keys), course_title) %>%
    dplyr::mutate(course_title = dplyr::na_if(trimws(as.character(course_title)), "")) %>%
    dplyr::filter(!is.na(course_title)) %>%
    dplyr::count(dplyr::across(dplyr::all_of(c(title_keys, "course_title"))),
                 name = ".title_rows") %>%
    dplyr::arrange(dplyr::across(dplyr::all_of(title_keys)),
                   dplyr::desc(.title_rows), course_title) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(title_keys))) %>%
    dplyr::slice_head(n = 1L) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.title_rows)

  if (has_title) {
    df <- df %>%
      dplyr::mutate(.classlist_course_title = dplyr::na_if(trimws(as.character(course_title)), "")) %>%
      dplyr::select(-course_title)
  }

  joined <- df %>%
    dplyr::left_join(title_source, by = title_keys, relationship = "many-to-one")
  if (has_title) {
    joined <- joined %>%
      dplyr::mutate(course_title = dplyr::coalesce(.classlist_course_title, course_title)) %>%
      dplyr::select(-.classlist_course_title)
  }
  joined
}


#' Select true class-list waitlist-demand rows
#'
#' Keeps waitlisted students who do not also hold a registered row for the same
#' campus, college (when present), term, part of term (when present), course
#' title, and subject/course. Registration codes are preferred; the display
#' status remains supported for backward-compatible callers.
#' @param df Student enrollment rows containing waitlist and registered statuses.
#' @param sections Optional sections table used when course titles are absent.
#' @return Waitlist rows after registered overlap is removed.
#' @keywords internal
get_true_waitlisted_rows <- function(df, sections = NULL) {
  df <- ensure_waitlist_course_title(df, sections) %>% dplyr::ungroup()

  if ("registration_status_code" %in% names(df)) {
    is_waitlisted <- df$registration_status_code %in% STATUS_WAITLIST
    is_registered <- df$registration_status_code %in% STATUS_REGISTERED
  } else if ("registration_status" %in% names(df)) {
    is_waitlisted <- df$registration_status == "Wait Listed"
    is_registered <- grepl("Registered", df$registration_status, ignore.case = TRUE)
  } else {
    stop("[waitlist-demand.R] input needs registration_status_code or registration_status")
  }

  optional_keys <- c("college", "part_term")
  identity_keys <- c("campus", optional_keys[optional_keys %in% names(df)],
                     "term", "subject_course", "course_title", "student_id")
  missing_keys <- setdiff(c("campus", "term", "subject_course", "course_title", "student_id"),
                          names(df))
  if (length(missing_keys) > 0L) {
    stop("[waitlist-demand.R] input is missing waitlist identity column(s): ",
         paste(missing_keys, collapse = ", "))
  }

  registered_keys <- df[is_registered, , drop = FALSE] %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(identity_keys)))

  df[is_waitlisted, , drop = FALSE] %>%
    dplyr::anti_join(registered_keys, by = identity_keys)
}


#' Summarize true waitlist demand at a requested reporting grain
#'
#' @param waitlisted_students Output from [get_true_waitlisted_rows()].
#' @param group_cols Columns defining one displayed waitlist group.
#' @param count_name Name for the distinct-student count column.
#' @return One row per reporting group with a distinct-student count.
#' @keywords internal
summarize_waitlist_demand <- function(waitlisted_students, group_cols,
                                      count_name = "waiting") {
  missing_cols <- setdiff(c(group_cols, "student_id"), names(waitlisted_students))
  if (length(missing_cols) > 0L) {
    stop("[waitlist-demand.R] cannot summarize; missing column(s): ",
         paste(missing_cols, collapse = ", "))
  }

  waitlisted_students %>%
    dplyr::ungroup() %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(c(group_cols, "student_id")))) %>%
    dplyr::count(dplyr::across(dplyr::all_of(group_cols)), name = count_name)
}


#' Summarize true waitlist demand by course
#'
#' Uses the canonical Waitlists reporting grain, carrying college and part of
#' term when the class list provides them.
#' @param waitlisted_students True waitlist-demand rows.
#' @return One row per course group with a distinct-student `count`.
#' @keywords internal
summarize_waitlist_courses <- function(waitlisted_students) {
  optional_keys <- c("college", "part_term")
  group_cols <- c("campus", optional_keys[optional_keys %in% names(waitlisted_students)],
                  "term", "subject_course", "course_title")
  summarize_waitlist_demand(waitlisted_students, group_cols, count_name = "count")
}


#' Summarize true waitlist demand by demographic groups
#'
#' @param waitlisted_students True waitlist-demand rows.
#' @param group_cols Columns defining the requested demographic breakdown.
#' @return One row per group with a distinct-student `count`.
#' @keywords internal
summarize_waitlist_groups <- function(waitlisted_students, group_cols) {
  summarize_waitlist_demand(waitlisted_students, group_cols, count_name = "count")
}


#' Calculate class-list true waitlist demand for a filtered scope
#'
#' This is the shared entry point for app surfaces. It filters the full class
#' list before removing registered overlap, which ensures the exclusion uses the
#' same user-facing scope as the displayed count.
#' @param students cedar_students enrollment rows.
#' @param opt Options accepted by [filter_class_list()].
#' @param sections Optional sections table for title enrichment.
#' @param group_cols Reporting grain. Defaults to the Waitlists course overview.
#' @param count_name Name for the distinct-student count column.
#' @return One row per reporting group with the requested count column.
#' @keywords internal
get_classlist_waitlist_demand <- function(students, opt, sections = NULL,
                                          group_cols = NULL,
                                          count_name = "waiting") {
  scoped <- filter_class_list(students, opt)
  true_waitlisted <- get_true_waitlisted_rows(scoped, sections)

  if (is.null(group_cols)) {
    optional_keys <- c("college", "part_term")
    group_cols <- c("campus", optional_keys[optional_keys %in% names(true_waitlisted)],
                    "term", "subject_course", "course_title")
  }
  summarize_waitlist_demand(true_waitlisted, group_cols, count_name)
}
