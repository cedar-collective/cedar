#' Analyze Cancelled Course Sections
#'
#' Returns cancelled section rows and summary tables for the Explore >
#' Cancellations page. Cancellation is defined narrowly as section status "C";
#' related non-active statuses are counted separately for page context.
#'
#' @param sections CEDAR sections table.
#' @param opt Filter options compatible with filter_DESRs().
#'
#' @return Named list with cancelled sections, summary tables, and status notes.
#' @export
get_cancellations <- function(sections, opt = list()) {
  required_cols <- c(
    "section_id", "term", "crn", "subject_course", "course_title", "section",
    "campus", "college", "department", "part_term", "delivery_method",
    "level", "enrolled", "capacity", "available", "status", "comments",
    "census1"
  )
  missing_cols <- setdiff(required_cols, names(sections))
  if (length(missing_cols) > 0) {
    stop("get_cancellations requires cedar_sections columns: ",
         paste(missing_cols, collapse = ", "))
  }

  if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
    cedar_debug("[cancellations] Starting with ", nrow(sections), " section rows.")
  }

  base_opt <- opt
  base_opt$status <- NULL
  # filter_DESRs is called twice, so the exclude-list flag must be set on both opts.
  base_opt$uel <- TRUE

  scoped_sections <- filter_DESRs(sections, base_opt) %>%
    dplyr::ungroup()

  status_note <- scoped_sections %>%
    dplyr::filter(status %in% c("R", "S")) %>%
    dplyr::count(status, name = "n_sections") %>%
    dplyr::right_join(
      tibble::tibble(
        status = c("R", "S"),
        status_label = c("Removed", "Suspended")
      ),
      by = "status"
    ) %>%
    dplyr::mutate(n_sections = dplyr::coalesce(n_sections, 0L)) %>%
    dplyr::select(status, status_label, n_sections)

  cancel_opt <- opt
  cancel_opt$status <- "C"
  # Keep this in sync with base_opt so the R/S note and cancelled rows use the same scope.
  cancel_opt$uel <- TRUE

  cancelled <- filter_DESRs(sections, cancel_opt) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      cancel_date_text = stringr::str_extract(
        comments,
        "(?i)(?<=canceled on )\\d{1,2}/\\d{1,2}/\\d{4}"
      ),
      canceled_on = as.Date(cancel_date_text, format = "%m/%d/%Y"),
      days_before_census = as.integer(census1 - canceled_on),
      term_label = fmt_term(term)
    ) %>%
    dplyr::select(
      section_id, term, term_label, department, subject_course, course_title,
      section, crn, campus, college, part_term, delivery_method, level,
      enrolled, capacity, available, status, canceled_on, census1,
      days_before_census, comments
    )

  if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
    cedar_debug("[cancellations] Found ", nrow(cancelled), " status C rows.")
  }

  by_department_term <- cancelled %>%
    dplyr::count(term, term_label, department, name = "n_cancelled") %>%
    dplyr::arrange(term, department)

  trend_opt <- cancel_opt
  trend_terms <- tolower(as.character(opt$term %||% character()))
  trend_seasons <- character()
  if (length(trend_terms) > 0 && all(trend_terms %in% c("fall", "spring", "summer"))) {
    trend_seasons <- trend_terms
  }
  trend_opt$term <- NULL

  trends <- filter_DESRs(sections, trend_opt) %>%
    dplyr::ungroup() %>%
    {
      if (length(trend_seasons) == 0) {
        .
      } else {
        dplyr::filter(
          .,
          substring(as.character(term), 5, 6) %in%
            c(fall = "80", spring = "10", summer = "60")[trend_seasons]
        )
      }
    } %>%
    dplyr::mutate(term_label = fmt_term(term)) %>%
    dplyr::count(term, term_label, department, name = "n_cancelled") %>%
    dplyr::arrange(term, department)

  timing <- cancelled %>%
    dplyr::filter(!is.na(days_before_census),
                  days_before_census >= 0,
                  days_before_census <= 100) %>%
    dplyr::count(department, days_before_census, name = "n_cancelled") %>%
    dplyr::arrange(department, days_before_census)

  timing_omitted <- cancelled %>%
    dplyr::filter(!is.na(days_before_census), days_before_census > 100) %>%
    dplyr::summarize(n_cancelled_sections = dplyr::n(), .groups = "drop") %>%
    dplyr::pull(n_cancelled_sections)

  common_courses <- cancelled %>%
    dplyr::group_by(campus, college, subject_course, course_title) %>%
    dplyr::summarize(
      n_cancelled_sections = dplyr::n(),
      n_terms_cancelled = dplyr::n_distinct(term),
      first_cancelled_term = min(term, na.rm = TRUE),
      last_cancelled_term = max(term, na.rm = TRUE),
      median_days_before_census = stats::median(days_before_census, na.rm = TRUE),
      cancelled_before_census = sum(!is.na(days_before_census) & days_before_census >= 0),
      cancelled_after_census = sum(!is.na(days_before_census) & days_before_census < 0),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      median_days_before_census = dplyr::if_else(
        is.nan(median_days_before_census),
        NA_real_,
        median_days_before_census
      ),
      first_cancelled_term = fmt_term(first_cancelled_term),
      last_cancelled_term = fmt_term(last_cancelled_term)
    ) %>%
    dplyr::arrange(dplyr::desc(n_cancelled_sections),
                   dplyr::desc(n_terms_cancelled),
                   campus, college, subject_course)

  list(
    cancelled_sections = cancelled,
    by_department_term = by_department_term,
    trends = trends,
    timing = timing,
    timing_omitted = timing_omitted,
    common_courses = common_courses,
    status_note = status_note
  )
}
