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
    "start_date", "census1"
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
      cancel_date_text = stringr::str_match(
        comments,
        "(?i)cancel(?:l)?ed\\s*(?:on|:)?\\s*(\\d{1,2}/\\d{1,2}/\\d{4})"
      )[, 2],
      canceled_on = as.Date(cancel_date_text, format = "%m/%d/%Y"),
      timing_reference_date = dplyr::coalesce(start_date, census1),
      timing_reference = dplyr::if_else(
        !is.na(start_date),
        "start_date",
        "census1"
      ),
      days_before_start = as.integer(timing_reference_date - canceled_on),
      days_before_census = as.integer(census1 - canceled_on),
      term_label = fmt_term(term)
    ) %>%
    dplyr::select(
      section_id, term, term_label, department, subject_course, course_title,
      section, crn, campus, college, part_term, delivery_method, level,
      enrolled, capacity, available, status, canceled_on, start_date, census1,
      timing_reference_date, timing_reference, days_before_start,
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
    dplyr::filter(!is.na(days_before_start),
                  days_before_start >= 0,
                  days_before_start <= 100) %>%
    dplyr::count(department, days_before_start, name = "n_cancelled") %>%
    dplyr::arrange(department, days_before_start)

  timing_omitted <- cancelled %>%
    dplyr::filter(!is.na(days_before_start), days_before_start > 100) %>%
    dplyr::summarize(n_cancelled_sections = dplyr::n(), .groups = "drop") %>%
    dplyr::pull(n_cancelled_sections)

  timing_summary <- tibble::tibble(
    total_cancelled = nrow(cancelled),
    parsed_cancel_date = sum(!is.na(cancelled$canceled_on)),
    missing_cancel_date = sum(is.na(cancelled$canceled_on)),
    missing_start_date = sum(!is.na(cancelled$canceled_on) & is.na(cancelled$start_date)),
    missing_census_date = sum(!is.na(cancelled$canceled_on) & is.na(cancelled$census1)),
    missing_timing_reference = sum(!is.na(cancelled$canceled_on) &
                                     is.na(cancelled$timing_reference_date)),
    timing_window_0_100 = sum(!is.na(cancelled$days_before_start) &
                                cancelled$days_before_start >= 0 &
                                cancelled$days_before_start <= 100),
    earlier_than_100_days = sum(!is.na(cancelled$days_before_start) &
                                  cancelled$days_before_start > 100),
    after_start = sum(!is.na(cancelled$days_before_start) &
                        cancelled$days_before_start < 0),
    parse_rate = dplyr::if_else(
      nrow(cancelled) > 0,
      parsed_cancel_date / total_cancelled,
      NA_real_
    )
  )

  common_courses <- if (nrow(cancelled) == 0) {
    tibble::tibble(
      campus = character(),
      college = character(),
      subject_course = character(),
      course_title = character(),
      n_cancelled_sections = integer(),
      n_terms_cancelled = integer(),
      first_cancelled_term = character(),
      last_cancelled_term = character(),
      median_days_before_start = double(),
      cancelled_before_start = integer(),
      cancelled_after_start = integer()
    )
  } else {
    cancelled %>%
      dplyr::group_by(campus, college, subject_course, course_title) %>%
      dplyr::summarize(
        n_cancelled_sections = dplyr::n(),
        n_terms_cancelled = dplyr::n_distinct(term),
        first_cancelled_term = min(term, na.rm = TRUE),
        last_cancelled_term = max(term, na.rm = TRUE),
        median_days_before_start = stats::median(days_before_start, na.rm = TRUE),
        cancelled_before_start = sum(!is.na(days_before_start) & days_before_start >= 0),
        cancelled_after_start = sum(!is.na(days_before_start) & days_before_start < 0),
        .groups = "drop"
      ) %>%
      dplyr::mutate(
        median_days_before_start = dplyr::if_else(
          is.nan(median_days_before_start),
          NA_real_,
          median_days_before_start
        ),
        first_cancelled_term = fmt_term(first_cancelled_term),
        last_cancelled_term = fmt_term(last_cancelled_term)
      ) %>%
      dplyr::arrange(dplyr::desc(n_cancelled_sections),
                     dplyr::desc(n_terms_cancelled),
                     campus, college, subject_course)
  }

  list(
    cancelled_sections = cancelled,
    by_department_term = by_department_term,
    trends = trends,
    timing = timing,
    timing_omitted = timing_omitted,
    timing_summary = timing_summary,
    common_courses = common_courses,
    status_note = status_note
  )
}
