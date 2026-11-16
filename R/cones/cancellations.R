#' Analyze Cancelled Course Sections
#'
#' Returns cancelled section rows and summary tables for the Bird's Eye >
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
      term_label = term_code_to_axis_label(term)
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
    dplyr::mutate(term_label = term_code_to_axis_label(term)) %>%
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


# ── Plot prep ────────────────────────────────────────────────────────────────

#' Department bars for Cancellations > By Department
#'
#' One row per department and term with the department's total across the
#' selected terms, departments ordered by that total (largest first, ties by
#' name). Every department is drawn on one scale, so a department with one
#' cancellation reads as one, not as a full bar.
#'
#' @param by_department_term `get_cancellations()$by_department_term`.
#' @return Tibble: `department` (factor, smallest total first so plotly draws
#'   the largest at the top), `term`, `term_label` (ordered factor), `n_cancelled`,
#'   `dept_total`.
prepare_cancellations_dept_plot_data <- function(by_department_term) {
  required <- c("term", "term_label", "department", "n_cancelled")
  missing <- setdiff(required, names(by_department_term))
  if (length(missing)) stop("prepare_cancellations_dept_plot_data needs columns: ", paste(missing, collapse = ", "))
  totals <- by_department_term %>%
    dplyr::group_by(department) %>%
    dplyr::summarize(dept_total = sum(n_cancelled), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(dept_total), department)
  by_department_term %>%
    dplyr::left_join(totals, by = "department") %>%
    dplyr::mutate(
      department = factor(department, levels = rev(totals$department)),
      term_label = term_axis_factor(term)
    ) %>%
    dplyr::select(department, term, term_label, n_cancelled, dept_total) %>%
    dplyr::arrange(dplyr::desc(department), term)
}

#' Pixel height for the department bars: one row per department
cancellations_dept_plot_height <- function(plot_data) {
  max(240L, 26L * dplyr::n_distinct(plot_data$department) + 110L)
}


# ── Plotting ─────────────────────────────────────────────────────────────────

#' Horizontal bars of cancelled sections by department, on one shared scale
#'
#' Several terms stack in chronological order, light to dark in one hue; the
#' department's total is labelled at the end of its bar.
#'
#' @param plot_data `prepare_cancellations_dept_plot_data()` output.
#' @return A plotly object.
plot_cancellations_by_department <- function(plot_data) {
  terms <- levels(droplevels(plot_data$term_label))
  colors <- if (length(terms) == 1L) unname(CEDAR_COLORS["blue"]) else
    grDevices::colorRampPalette(unname(CEDAR_COLORS[c("blue_light", "blue_dark")]))(length(terms))
  totals <- dplyr::distinct(plot_data, department, dept_total)
  p <- plotly::plot_ly(height = cancellations_dept_plot_height(plot_data))
  for (i in seq_along(terms)) {
    rows <- plot_data[plot_data$term_label == terms[i], ]
    p <- plotly::add_bars(p, data = rows, x = ~n_cancelled, y = ~department, orientation = "h",
      name = terms[i], marker = list(color = colors[i], line = list(color = "#ffffff", width = 1)),
      hovertext = ~paste0(department, " · ", term_label, ": ", n_cancelled, " cancelled"),
      hoverinfo = "text", textposition = "none")
  }
  plotly::layout(p,
    barmode = "stack", bargap = 0.3,
    xaxis = list(title = "Cancelled sections", rangemode = "tozero", zeroline = FALSE,
                 range = c(0, max(totals$dept_total) * 1.12)),
    yaxis = list(title = "", categoryorder = "array", categoryarray = levels(plot_data$department),
                 automargin = TRUE),
    showlegend = length(terms) > 1L,
    legend = list(orientation = "h", x = 0, y = 1, yanchor = "bottom", traceorder = "normal"),
    margin = list(t = if (length(terms) > 1L) 40 else 10, r = 20),
    annotations = lapply(seq_len(nrow(totals)), function(i) list(
      x = totals$dept_total[i], y = as.character(totals$department[i]), text = totals$dept_total[i],
      xanchor = "left", xshift = 4, showarrow = FALSE, font = list(size = 11))))
}
